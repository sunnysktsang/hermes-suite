#!/bin/bash
# =============================================================================
# logs.sh — Tail Hermes Suit container logs
# =============================================================================
set -e

export PATH="$HOME/.local/bin:$PATH"

COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/docker-compose.yaml"
podman-compose -f "${COMPOSE_FILE}" logs -f
