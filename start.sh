#!/bin/bash
# =============================================================================
# start.sh — Hermes Suite container entrypoint
# Handles UID/GID remapping, directory setup, and launches supervisord.
# Detects Podman vs Docker to choose the appropriate privilege model.
# Detection uses /proc/1/cgroup (reliable at runtime) rather than
# /run/.containerenv (can be baked into the image by Podman at build time).
#
# Podman path:  root → chown → s6-setuidgid hermes → re-exec → setup → supervisord (as hermes)
# Docker path:  root → setup → chown → supervisord (as root, children as hermes via user=)
# =============================================================================
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

# --- Helper: runtime detection ---
# Detect Docker runtime. We check /.dockerenv first (created by Docker at
# runtime, not by Podman) to handle cgroup v2 where /proc/1/cgroup shows
# "0::/". Then fall back to cgroup v1 check as a backup. Podman-built images
# may contain a stale /run/.containerenv baked into the image layer, so that
# file alone is unreliable.
is_docker() {
    [ -f /.dockerenv ] && return 0
    grep -qaE '/docker/|docker-|containerd' /proc/1/cgroup 2>/dev/null && return 0
    return 1
}

# --- Helper: dashboard auth credential setup ---
# Upstream v2026.7.1 removed unauthenticated public dashboard access.
# Credentials are provided via DASHBOARD_CREDENTIAL env var (format:
# "username:password"), set by up.sh from versions.env. Parse and export
# the two vars the dashboard's BasicAuthProvider reads.
setup_dashboard_auth() {
    local cred="${DASHBOARD_CREDENTIAL:-admin:admin}"
    DASH_USER="${cred%%:*}"
    DASH_PASS="${cred#*:}"
    export HERMES_DASHBOARD_BASIC_AUTH_USERNAME="$DASH_USER"
    export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="$DASH_PASS"
}

# --- Helper: directory and config setup (shared by both paths) ---
setup_hermes() {
    source "${INSTALL_DIR}/.venv/bin/activate"

    # Create essential directory structure (mirrors official entrypoint)
    mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home,webui,cache}

    # .env — only create if missing (newer agent images may not ship .env.example)
    if [ ! -f "$HERMES_HOME/.env" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
        cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
        echo "Created default .env — edit $HERMES_HOME/.env to add your API keys"
    fi

    # config.yaml — only create if missing
    if [ ! -f "$HERMES_HOME/config.yaml" ] && [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
        cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
        echo "Created default config.yaml"
    fi

    # Ensure config permissions
    if [ -f "$HERMES_HOME/config.yaml" ]; then
        chown hermes:hermes "$HERMES_HOME/config.yaml"
        chmod 640 "$HERMES_HOME/config.yaml"
    fi

    # SOUL.md — only create if missing
    if [ ! -f "$HERMES_HOME/SOUL.md" ] && [ -f "$INSTALL_DIR/docker/SOUL.md" ]; then
        cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
    fi

    # Sync bundled skills
    if [ -d "$INSTALL_DIR/skills" ]; then
        python3 "$INSTALL_DIR/tools/skills_sync.py" 2>/dev/null || true
    fi

    # --- Dashboard basic auth (upstream v2026.7.1 security hardening) ---
    setup_dashboard_auth

    # --- Clean up stale PID/lock files from previous container runs ---
    for f in gateway.pid gateway.lock; do
        if [ -f "$HERMES_HOME/$f" ]; then
            echo "Removing stale $f from previous container run"
            rm -f "$HERMES_HOME/$f"
        fi
    done

    # --- Ensure supervisord directories exist ---
    mkdir -p /var/log/supervisor /var/run/supervisor
}

# --- Helper: startup banner ---
print_banner() {
    echo "=========================================="
    echo " Hermes Suite — All-in-One Container"
    echo "=========================================="
    echo " Gateway:    http://0.0.0.0:8642"
    echo " Dashboard:  http://0.0.0.0:9119"
    echo " WebUI:      http://0.0.0.0:8787"
    echo "=========================================="
    echo " Dashboard login: $HERMES_DASHBOARD_BASIC_AUTH_USERNAME / $HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
    echo "=========================================="
}

# =============================================================================
# Main entry point
# =============================================================================
if [ "$(id -u)" = "0" ]; then
    # --- Privilege dropping (mirrors official hermes-agent entrypoint) ---
    if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
        echo "Changing hermes UID to $HERMES_UID"
        usermod -u "$HERMES_UID" hermes
    fi

    if [ -n "$HERMES_GID" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
        echo "Changing hermes GID to $HERMES_GID"
        groupmod -o -g "$HERMES_GID" hermes 2>/dev/null || true
    fi

    actual_hermes_uid=$(id -u hermes)
    if [ "$(stat -c %u "$HERMES_HOME" 2>/dev/null)" != "$actual_hermes_uid" ]; then
        echo "$HERMES_HOME is not owned by $actual_hermes_uid, fixing"
        chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || \
            echo "Warning: chown failed (rootless container?) — continuing anyway"
    fi

    # --- Runtime-specific startup ---
    if is_docker; then
        # Docker: stay as root for supervisord (fixes /dev/stdout permission issue)
        # supervisord.conf user=hermes ensures child processes run as hermes
        echo "Detected Docker runtime — supervisord as root, services as hermes"
        setup_hermes

        # Ensure all created files/dirs are owned by hermes
        chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || \
            echo "Warning: chown failed — continuing anyway"

        print_banner
        exec "$@"
    fi

    # Podman (or unknown runtime): drop to hermes via s6-setuidgid, re-exec this script
    # s6-setuidgid is provided by the s6-overlay in the base agent image (v2026.5.29+)
    echo "Detected Podman runtime"
    echo "Dropping root privileges"
    exec /command/s6-setuidgid hermes "$0" "$@"
fi

# --- Running as hermes (Podman path only, via s6-setuidgid re-exec) ---
setup_hermes
print_banner
exec "$@"