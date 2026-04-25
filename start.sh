#!/bin/bash
# =============================================================================
# start.sh — Hermes Suit container entrypoint
# Handles UID/GID remapping, directory setup, and launches supervisord.
# Modeled after the official hermes-agent entrypoint.sh.
# =============================================================================
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

# --- Privilege dropping (mirrors official hermes-agent entrypoint) ---
if [ "$(id -u)" = "0" ]; then
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

    echo "Dropping root privileges"
    exec gosu hermes "$0" "$@"
fi

# --- Running as hermes from here ---
source "${INSTALL_DIR}/.venv/bin/activate"

# Create essential directory structure (mirrors official entrypoint)
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home,webui,cache}

# .env — only create if missing
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
    echo "Created default .env — edit $HERMES_HOME/.env to add your API keys"
fi

# config.yaml — only create if missing
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
    echo "Created default config.yaml"
fi

# Ensure config permissions
if [ -f "$HERMES_HOME/config.yaml" ]; then
    chown hermes:hermes "$HERMES_HOME/config.yaml"
    chmod 640 "$HERMES_HOME/config.yaml"
fi

# SOUL.md — only create if missing
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Sync bundled skills
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py" 2>/dev/null || true
fi

# --- Clean up stale PID/lock files from previous container runs ---
# These live on the mounted volume and survive container restarts.
# Without cleanup, the gateway thinks a previous instance is still running.
for f in gateway.pid gateway.lock; do
    if [ -f "$HERMES_HOME/$f" ]; then
        echo "Removing stale $f from previous container run"
        rm -f "$HERMES_HOME/$f"
    fi
done

# --- Ensure supervisord directories exist ---
mkdir -p /var/log/supervisor /var/run/supervisor

echo "=========================================="
echo " Hermes Suit — All-in-One Container"
echo "=========================================="
echo " Gateway:    http://0.0.0.0:8642"
echo " Dashboard:  http://0.0.0.0:9119"
echo " WebUI:      http://0.0.0.0:8787"
echo "=========================================="

# Execute the CMD (supervisord)
exec "$@"
