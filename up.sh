#!/bin/bash
# =============================================================================
# up.sh — Start Hermes Suit container
# =============================================================================
set -e

# Ensure podman-compose is findable (pip install puts it in ~/.local/bin)
export PATH="$HOME/.local/bin:$PATH"

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/docker-compose.yaml"

# Create the network if it doesn't already exist
if ! podman network exists agent_net 2>/dev/null; then
    echo "Creating network agent_net (10.99.0.0/24)..."
    podman network create --subnet 10.99.0.0/24 agent_net
    # Podman 3.4.4 generates CNI config v1.0.0 but the firewall plugin only supports 0.4.0
    sed -i 's/"cniVersion": "1.0.0"/"cniVersion": "0.4.0"/' \
        ~/.config/cni/net.d/agent_net.conflist 2>/dev/null || true
fi

podman-compose -f "${COMPOSE_FILE}" up -d

echo ""
echo "Hermes Suit is running:"
echo "  Gateway:    http://localhost:8642"
echo "  WebUI:      http://localhost:8787"
echo "  Dashboard:  http://localhost:9119"
echo ""
echo " Logs: podman-compose -f ${COMPOSE_FILE} logs -f"
echo " Stop: podman-compose -f ${COMPOSE_FILE} down"
