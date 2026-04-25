#!/bin/bash
# =============================================================================
# build.sh — Build the Hermes Suit container image
# =============================================================================
set -e

IMAGE_NAME="hermes-suit:v1"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo " Building Hermes Suit: ${IMAGE_NAME}"
echo " Build context: ${BUILD_DIR}"
echo "=========================================="

podman build \
    -t "${IMAGE_NAME}" \
    --format docker \
    "${BUILD_DIR}"

echo ""
echo "=========================================="
echo " Build complete: ${IMAGE_NAME}"
echo "=========================================="
echo ""
echo " Run as a Service (Compose):"
echo "   podman-compose -f ${BUILD_DIR}/docker-compose.yaml up -d"
echo ""
echo " Run Manually (Interactive/Debug):"
echo "   podman run --rm -it \\"
echo "     -v ~/.hermes:/opt/data:Z \\"
echo "     -p 8642:8642 -p 8787:8787 -p 9119:9119 \\"
echo "     ${IMAGE_NAME}"
