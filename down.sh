#!/bin/bash
# =============================================================================
# down.sh — Stop Hermes Suit container
# =============================================================================
set -e

export PATH="$HOME/.local/bin:$PATH"

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/docker-compose.yaml"
podman-compose -f "${COMPOSE_FILE}" down

echo "Hermes Suit stopped."
