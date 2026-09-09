#!/bin/bash
# =============================================================================
# build.sh — Build the Hermes Suite container image
#
# Reads pinned versions from versions.env by default.
# Override with: ./build.sh --agent v2026.7.20 --webui v0.52.106
#
# CONTAINER_RUNTIME (from versions.env or CLI flag):
#   auto         — detect podman first, fall back to docker (default)
#   podman       — build with podman, supervisord logs to /dev/stdout
#   docker       — build with docker, supervisord logs to /dev/stdout
#   docker-nolog — build with docker, supervisord logs to /dev/null
#
# USE_SUDO (from versions.env):
#   false — run build command directly (default)
#   true  — prefix build command with sudo (for rootful podman/docker)
#
# ENABLE_WHATSAPP_BRIDGE (from versions.env or --whatsapp flag):
#   false — exclude WhatsApp bridge from image (default)
#   true  — include WhatsApp bridge in image
#
# Note: Docker CE is auto-detected at container startup (start.sh).
# The universal image works on both Podman and Docker out of the box.
# =============================================================================
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Load pinned versions and runtime from versions.env ---
if [ -f "${BUILD_DIR}/versions.env" ]; then
    eval "$(grep -E '^(AGENT_VERSION|WEBUI_VERSION|CONTAINER_RUNTIME|USE_SUDO|ENABLE_WHATSAPP_BRIDGE|ENABLE_BROWSER)=' "${BUILD_DIR}/versions.env")"
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
        --podman)
            CONTAINER_RUNTIME="podman"; shift ;;
        --docker)
            CONTAINER_RUNTIME="docker"; shift ;;
        --docker-nolog)
            CONTAINER_RUNTIME="docker-nolog"; shift ;;
        --sudo)
            USE_SUDO="true"; shift ;;
        --no-sudo)
            USE_SUDO="false"; shift ;;
        --whatsapp)
            ENABLE_WHATSAPP_BRIDGE="true"; shift ;;
        --no-browser)
            ENABLE_BROWSER="false"; shift ;;
        --browser)
            ENABLE_BROWSER="true"; shift ;;
        *)
            echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Auto-detect container runtime ---
if [ "$CONTAINER_RUNTIME" = "auto" ]; then
    if command -v podman &>/dev/null; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker &>/dev/null; then
        CONTAINER_RUNTIME="docker"
    else
        echo "ERROR: Neither podman nor docker found. Install one or set CONTAINER_RUNTIME in versions.env."
        exit 1
    fi
fi

# --- Derive build command and mode from runtime ---
case "$CONTAINER_RUNTIME" in
    podman)
        BUILD_CMD="podman"
        BUILD_MODE="podman"
        ;;
    docker)
        BUILD_CMD="docker"
        BUILD_MODE="docker"
        ;;
    docker-nolog)
        BUILD_CMD="docker"
        BUILD_MODE="docker-nolog"
        ;;
    *)
        echo "ERROR: Unknown CONTAINER_RUNTIME value: $CONTAINER_RUNTIME"
        echo "Valid options: auto, podman, docker, docker-nolog"
        exit 1
        ;;
esac

# --- Determine sudo prefix ---
SUDO_PREFIX=""
if [ "$USE_SUDO" = "true" ]; then
    SUDO_PREFIX="sudo"
fi

# Strip 'v' prefix for the compound tag (Docker convention: no 'v')
AGENT_VER_CLEAN="${AGENT_VERSION#v}"
WEBUI_VER_CLEAN="${WEBUI_VERSION#v}"

# --- Browser tooling option (ENABLE_BROWSER, default true) ---
# Skipping Playwright/Chromium produces a smaller, faster-building image
# for low-resource edge devices. Content-different images get a -slim
# tag suffix so they cannot be confused with the default image.
ENABLE_BROWSER="${ENABLE_BROWSER:-true}"
case "$ENABLE_BROWSER" in
    true|false) ;;
    *)
        echo "ERROR: ENABLE_BROWSER must be true or false (got '$ENABLE_BROWSER')"
        exit 1
        ;;
esac
IMAGE_SUFFIX=""
if [ "$ENABLE_BROWSER" = "false" ]; then
    IMAGE_SUFFIX="-slim"
fi
IMAGE_TAG="ascensionoid/hermes-suite:${AGENT_VER_CLEAN}-${WEBUI_VER_CLEAN}${IMAGE_SUFFIX}"

# Persist the effective browser setting back to versions.env when it deviates
# from what the file records. up.sh/down.sh derive the image tag from
# versions.env; without this, "./build.sh --no-browser && ./up.sh" would
# silently run the full image under the non-slim tag (flag/env asymmetry).
# Default builds (nothing set, or file already matches) leave the file
# untouched — in particular the commented example stays a comment. Only an
# UNCOMMENTED line counts as the file's recorded setting.
FILE_BROWSER="$(grep -E '^ENABLE_BROWSER=' "${BUILD_DIR}/versions.env" 2>/dev/null | tail -1 | cut -d= -f2)"
if [ "$ENABLE_BROWSER" != "${FILE_BROWSER:-true}" ]; then
    if grep -qE '^#?ENABLE_BROWSER=' "${BUILD_DIR}/versions.env"; then
        sed -i -E "s|^#?ENABLE_BROWSER=.*|ENABLE_BROWSER=${ENABLE_BROWSER}|" "${BUILD_DIR}/versions.env"
    else
        printf '\nENABLE_BROWSER=%s\n' "$ENABLE_BROWSER" >> "${BUILD_DIR}/versions.env"
    fi
    echo " Browser setting persisted to versions.env: ENABLE_BROWSER=${ENABLE_BROWSER}"
fi

# --- Patch supervisord.conf for docker-nolog mode ---
if [ "$BUILD_MODE" = "docker-nolog" ]; then
    sed -i \
        -e 's|stdout_logfile=/dev/stdout|stdout_logfile=/dev/null|' \
        -e 's|stderr_logfile=/dev/stderr|stderr_logfile=/dev/null|' \
        "${BUILD_DIR}/supervisord.conf"
    echo "Docker nolog mode: child logs discarded"
fi

echo "=========================================="
echo " Building Hermes Suite"
echo "=========================================="
echo " Agent version:  ${AGENT_VERSION}"
echo " WebUI version:  ${WEBUI_VERSION}"
echo " Browser:        ${ENABLE_BROWSER}"
echo " Image tag:      ${IMAGE_TAG}"
echo " Runtime:        ${CONTAINER_RUNTIME}"
echo " Sudo:           ${USE_SUDO}"
echo " WhatsApp:       ${ENABLE_WHATSAPP_BRIDGE}"
echo " Build context:  ${BUILD_DIR}"
echo "=========================================="

# --- Build ---
if [ "$BUILD_CMD" = "podman" ]; then
    $SUDO_PREFIX podman build \
        --build-arg AGENT_VERSION="${AGENT_VERSION}" \
        --build-arg HERMES_WEBUI_VERSION="${WEBUI_VERSION}" \
        --build-arg ENABLE_WHATSAPP_BRIDGE="${ENABLE_WHATSAPP_BRIDGE}" \
        --build-arg INSTALL_BROWSER="${ENABLE_BROWSER}" \
        -t "${IMAGE_TAG}" \
        --format docker \
        "${BUILD_DIR}"
else
    $SUDO_PREFIX docker build \
        --build-arg AGENT_VERSION="${AGENT_VERSION}" \
        --build-arg HERMES_WEBUI_VERSION="${WEBUI_VERSION}" \
        --build-arg ENABLE_WHATSAPP_BRIDGE="${ENABLE_WHATSAPP_BRIDGE}" \
        --build-arg INSTALL_BROWSER="${ENABLE_BROWSER}" \
        -t "${IMAGE_TAG}" \
        "${BUILD_DIR}"
fi

# --- Restore supervisord.conf after docker-nolog build ---
if [ "$BUILD_MODE" = "docker-nolog" ]; then
    git -C "${BUILD_DIR}" checkout -- supervisord.conf 2>/dev/null || \
        sed -i \
            -e 's|stdout_logfile=/dev/null|stdout_logfile=/dev/stdout|' \
            -e 's|stderr_logfile=/dev/null|stderr_logfile=/dev/stderr|' \
            "${BUILD_DIR}/supervisord.conf"
    echo "Restored supervisord.conf to defaults"
fi

echo ""
echo "=========================================="
echo " Build complete: ${IMAGE_TAG}"
echo "=========================================="
echo ""
echo " Run as a Service (Compose):"
echo "   ./up.sh"
echo ""
echo " Run Manually (Interactive/Debug):"
if [ "$BUILD_CMD" = "podman" ]; then
    echo "   ${SUDO_PREFIX} podman run --rm -it \\"
else
    echo "   ${SUDO_PREFIX} docker run --rm -it \\"
fi
echo "     -v ~/.hermes:/opt/data:Z \\"
echo "     -p 8642:8642 -p 8787:8787 -p 9119:9119 \\"
echo "     ${IMAGE_TAG}"
