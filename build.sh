#!/bin/bash
# =============================================================================
# build.sh — Build the Hermes Suite container image
#
# Reads pinned versions from versions.env by default.
# Override with: ./build.sh --agent v2026.4.30 --webui v0.50.278
# =============================================================================
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Load pinned versions from versions.env ---
if [ -f "${BUILD_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION)=' "${BUILD_DIR}/versions.env")"
else
    echo "ERROR: versions.env not found in ${BUILD_DIR}"
    exit 1
fi

# --- Allow overrides via CLI args ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --agent)
            AGENT_VERSION="$2"; shift 2 ;;
        --webui)
            WEBUI_VERSION="$2"; shift 2 ;;
        *)
            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Strip 'v' prefix for the compound tag (Docker convention: no 'v')
AGENT_VER_CLEAN="${AGENT_VERSION#v}"
WEBUI_VER_CLEAN="${WEBUI_VERSION#v}"
IMAGE_TAG="ascensionoid/hermes-suite:${AGENT_VER_CLEAN}-${WEBUI_VER_CLEAN}"

echo "=========================================="
echo " Building Hermes Suite"
echo "=========================================="
echo " Agent version:  ${AGENT_VERSION}"
echo " WebUI version:  ${WEBUI_VERSION}"
echo " Image tag:      ${IMAGE_TAG}"
echo " Build context:  ${BUILD_DIR}"
echo "=========================================="

podman build \
    --build-arg AGENT_VERSION="${AGENT_VERSION}" \
    --build-arg HERMES_WEBUI_VERSION="${WEBUI_VERSION}" \
    -t "${IMAGE_TAG}" \
    --format docker \
    "${BUILD_DIR}"

echo ""
echo "=========================================="
echo " Build complete: ${IMAGE_TAG}"
echo "=========================================="
echo ""
echo " Run as a Service (Compose):"
echo "   podman-compose -f ${BUILD_DIR}/docker-compose.yaml up -d"
echo ""
echo " Run Manually (Interactive/Debug):"
echo "   podman run --rm -it \\"
echo "     -v ~/.hermes:/opt/data:Z \\"
echo "     -p 8642:8642 -p 8787:8787 -p 9119:9119 \\"
echo "     ${IMAGE_TAG}"
