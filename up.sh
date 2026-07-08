#!/bin/bash
# =============================================================================
# up.sh — Start Hermes Suite container
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yaml"

# --- Load config from versions.env ---
if [ -f "${SCRIPT_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION|CONTAINER_RUNTIME|USE_SUDO|DASHBOARD_CREDENTIAL)=' "${SCRIPT_DIR}/versions.env")"
fi
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-auto}"
USE_SUDO="${USE_SUDO:-false}"

# --- Dashboard credentials ---
# DASHBOARD_CREDENTIAL controls the dashboard login. Options:
#   admin:admin    — default, works immediately
#   auto           — auto-generate a random password (persisted, printed below)
#   user:password  — custom credentials
DASHBOARD_CREDENTIAL="${DASHBOARD_CREDENTIAL:-admin:admin}"

if [ "$DASHBOARD_CREDENTIAL" = "auto" ]; then
    CRED_FILE="${SCRIPT_DIR}/.dashboard_credential"
    if [ -f "$CRED_FILE" ]; then
        DASHBOARD_CREDENTIAL=$(cat "$CRED_FILE")
    else
        PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
        DASHBOARD_CREDENTIAL="admin:${PASSWORD}"
        echo "$DASHBOARD_CREDENTIAL" > "$CRED_FILE"
        chmod 600 "$CRED_FILE"
    fi
fi

export DASHBOARD_CREDENTIAL

# --- Auto-detect ---
if [ "$CONTAINER_RUNTIME" = "auto" ]; then
    if command -v podman &>/dev/null; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker &>/dev/null; then
        CONTAINER_RUNTIME="docker"
    else
        echo "ERROR: Neither podman nor docker found."
        exit 1
    fi
fi

# --- Determine sudo prefix ---
SUDO_PREFIX=""
if [ "$USE_SUDO" = "true" ]; then
    SUDO_PREFIX="sudo"
fi

# --- Derive image tag from versions.env ---
AGENT_VER_CLEAN="${AGENT_VERSION#v}"
WEBUI_VER_CLEAN="${WEBUI_VERSION#v}"
export HERMES_SUITE_IMAGE_TAG="${AGENT_VER_CLEAN}-${WEBUI_VER_CLEAN}"

# For sudo: compose needs explicit env passthrough
if [ "$USE_SUDO" = "true" ]; then
    COMPOSE_PREFIX="sudo env HERMES_SUITE_IMAGE_TAG=${HERMES_SUITE_IMAGE_TAG} DASHBOARD_CREDENTIAL=${DASHBOARD_CREDENTIAL}"
else
    COMPOSE_PREFIX=""
fi

# --- Create network and start ---
case "$CONTAINER_RUNTIME" in
    podman)
        export PATH="$HOME/.local/bin:$PATH"
        PODMAN_COMPOSE="$(command -v podman-compose)"
        NET_NAME=$(grep -m1 'external: true' "${COMPOSE_FILE}" -B1 | head -1 | sed 's/^[[:space:]]*//' | sed 's/:$//')
        NET_IP=$(grep -m1 "ipv4_address" "${COMPOSE_FILE}" | sed "s/.*: //" | tr -d "[:space:]")
        NET_SUBNET=$(echo "$NET_IP" | cut -d. -f1-3).0/24
        if ! $SUDO_PREFIX podman network exists "$NET_NAME" 2>/dev/null; then
            echo "Creating network $NET_NAME ($NET_SUBNET)..."
            $SUDO_PREFIX podman network create --subnet "$NET_SUBNET" "$NET_NAME"
            # Podman < 4 CNI version fix (firewall plugin doesn't support 1.0.0)
            PODMAN_VER=$(podman version -f '{{.Version}}' 2>/dev/null | cut -d. -f1)
            if [ "${PODMAN_VER:-4}" -lt 4 ]; then
                CNI_FILE=$(find /etc/cni/net.d/ ~/.config/cni/net.d/ -name "${NET_NAME}.conflist" 2>/dev/null | head -1)
                if [ -n "$CNI_FILE" ]; then
                    $SUDO_PREFIX sed -i 's/"cniVersion": "1.0.0"/"cniVersion": "0.4.0"/' "$CNI_FILE"
                fi
            fi
        fi
        $COMPOSE_PREFIX "$PODMAN_COMPOSE" -f "${COMPOSE_FILE}" up -d
        ;;
    docker|docker-nolog)
        NET_NAME=$(grep -m1 'external: true' "${COMPOSE_FILE}" -B1 | head -1 | sed 's/^[[:space:]]*//' | sed 's/:$//')
        NET_IP=$(grep -m1 "ipv4_address" "${COMPOSE_FILE}" | sed "s/.*: //" | tr -d "[:space:]")
        NET_SUBNET=$(echo "$NET_IP" | cut -d. -f1-3).0/24
        if ! $SUDO_PREFIX docker network inspect "$NET_NAME" &>/dev/null; then
            echo "Creating network $NET_NAME ($NET_SUBNET)..."
            $SUDO_PREFIX docker network create --subnet "$NET_SUBNET" "$NET_NAME"
        fi
        $COMPOSE_PREFIX docker compose -f "${COMPOSE_FILE}" up -d
        ;;
    *)
        echo "ERROR: Unknown CONTAINER_RUNTIME: $CONTAINER_RUNTIME"
        exit 1
        ;;
esac

echo ""
echo "Hermes Suite is running:"
echo "  Gateway:    http://localhost:8642"
echo "  WebUI:      http://localhost:8787"
echo "  Dashboard:  http://localhost:9119"
echo ""
DASH_USER="${DASHBOARD_CREDENTIAL%%:*}"
DASH_PASS="${DASHBOARD_CREDENTIAL#*:}"
echo "  Dashboard Login ID: $DASH_USER"
echo "  Dashboard Password: $DASH_PASS"
echo ""
echo "Logs: ./logs.sh"
echo "Stop: ./down.sh"
