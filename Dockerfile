# =============================================================================
# Hermes Suite — All-in-One Container Image
# Combines: hermes-agent + hermes-webui + hermes-dashboard
#
# Solves Podman v3.4.4 UID/GID sharing limitation between multiple containers
# by running all three services in a single container under one user.
#
# Services:
#   hermes-gateway   — Agent gateway on port 8642 (CLI, Telegram, cron, tools)
#   hermes-dashboard — Built-in monitoring dashboard on port 9119
#   hermes-webui     — Browser chat interface on port 8787
#
# Build:  podman build -t hermes-suite:2026.4.30-0.50.255 .
# Run:    podman-compose up -d
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Use the official hermes-agent image as the base
# This already contains: Python 3.13, Node.js, npm, Playwright, agent code,
# the built-in web dashboard (hermes dashboard), the gateway, uv, and gosu.
# ---------------------------------------------------------------------------
ARG AGENT_VERSION=v2026.4.30
FROM docker.io/nousresearch/hermes-agent:${AGENT_VERSION}

USER root

# ---------------------------------------------------------------------------
# Stage 2: Install system dependencies needed by all services
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo \
        git \
        curl \
        nano \
        net-tools \
        iputils-ping \
        iproute2 \
        openssh-client \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Allow hermes user to use sudo without password
RUN echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ---------------------------------------------------------------------------
# Stage 3: Install Tinker-Atropos reasoning engine (from current setup)
# Uses uv which is already present in the base image.
# ---------------------------------------------------------------------------
RUN uv pip install -e /opt/hermes/tinker-atropos

# ---------------------------------------------------------------------------
# Stage 4: Install Browser tool dependencies for agent
# npm install + Playwright chromium (needed by browser toolset)
# ---------------------------------------------------------------------------
RUN cd /opt/hermes && \
    npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium && \
    rm -rf /opt/hermes/scripts/whatsapp-bridge && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Stage 5: Install supervisord via uv (not available in Debian Trixie apt)
# We install it into a dedicated venv at /opt/supervisor.
# ---------------------------------------------------------------------------
RUN uv venv /opt/supervisor && \
    uv pip install --python /opt/supervisor/bin/python3 supervisor && \
    ln -sf /opt/supervisor/bin/supervisord /usr/local/bin/supervisord && \
    ln -sf /opt/supervisor/bin/supervisorctl /usr/local/bin/supervisorctl

RUN mkdir -p /var/log/supervisor /var/run/supervisor && \
    chown -R hermes:hermes /var/log/supervisor /var/run/supervisor

# ---------------------------------------------------------------------------
# Stage 6: Install hermes-webui
# The webui is a Python web server (server.py). We clone it from GitHub
# and set up its own venv using uv (avoids python3-venv package requirement).
# The webui needs the agent's Python deps to import agent modules.
#
# PIN to a specific tag for reproducible builds — never use 'master'.
# ---------------------------------------------------------------------------
ARG HERMES_WEBUI_VERSION=v0.50.255
RUN cd /opt && \
    git clone --depth 1 --branch ${HERMES_WEBUI_VERSION} \
        https://github.com/nesquena/hermes-webui.git hermes-webui && \
    uv venv /opt/hermes-webui/venv && \
    uv pip install --python /opt/hermes-webui/venv/bin/python3 --no-cache-dir -r /opt/hermes-webui/requirements.txt && \
    uv pip install --python /opt/hermes-webui/venv/bin/python3 --no-cache-dir -e "/opt/hermes[all]" && \
    rm -rf /opt/hermes-webui/.git

# Bake version tag into the webui
RUN echo "__version__ = '${HERMES_WEBUI_VERSION}'" > /opt/hermes-webui/api/_version.py

# ---------------------------------------------------------------------------
# Stage 7: Set up supervisord config and startup script
# ---------------------------------------------------------------------------
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY start.sh /opt/hermes-suite/start.sh
RUN chmod +x /opt/hermes-suite/start.sh

# ---------------------------------------------------------------------------
# Stage 8: Environment, labels, and runtime config
# ---------------------------------------------------------------------------
# Re-declare ARGs after FROM so they are available in LABEL
ARG AGENT_VERSION=v2026.4.30
ARG HERMES_WEBUI_VERSION=v0.50.255

LABEL org.opencontainers.image.title="Hermes Suite" \
      org.opencontainers.image.description="All-in-one: hermes-agent + hermes-webui + hermes-dashboard" \
      org.opencontainers.image.source="https://github.com/sunnysktsang/hermes-suite" \
      org.opencontainers.image.vendor="sunnysktsang" \
      hermes-suite.agent-version="${AGENT_VERSION}" \
      hermes-suite.webui-version="${HERMES_WEBUI_VERSION}"

ENV PATH="/opt/hermes/.venv/bin:/opt/hermes-webui/venv/bin:$PATH"
ENV HERMES_HOME=/opt/data
ENV HERMES_DATA_DIR=/opt/data
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# hermes-agent web dist (built into the base image)
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist

# hermes-webui settings
ENV HERMES_WEBUI_HOST=0.0.0.0
ENV HERMES_WEBUI_PORT=8787
ENV HERMES_WEBUI_STATE_DIR=/opt/data/webui
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes

# Expose all service ports
EXPOSE 8642 8787 9119

# Workspace directory
RUN mkdir -p /workspace

WORKDIR /opt/hermes

# Entrypoint: run start.sh which sets up config then launches supervisord
ENTRYPOINT ["/opt/hermes-suite/start.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
