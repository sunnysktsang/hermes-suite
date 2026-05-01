# Hermes Suite — All-in-One Container Image

Single Docker/Podman image combining three Hermes services:

| Service | Port | Description |
|---------|------|-------------|
| hermes-gateway | 8642 | Agent gateway (CLI, Telegram, cron, tools) |
| hermes-dashboard | 9119 | Monitoring/analytics dashboard (built-in) |
| hermes-webui | 8787 | Browser-based chat interface |

Pre-built multi-arch images available on [Docker Hub](https://hub.docker.com/r/ascensionoid/hermes-suite).

🏗️ Official docker images are maintained by Ascensionoid ([ascensionoid.com](https://ascensionoid.com)).

## Why This Exists

Podman v3.4.4 cannot share the same UID/GID between multiple containers easily.
The standard multi-container setup (hermes-agent + hermes-webui + hermes-dashboard)
requires each container to run as the same user to share the `~/.hermes` volume.
Podman v3.4.4 has limitations with `userns_mode: keep-id` across multiple containers.

This image solves that by running all three services in **one container** via supervisord.

## Architecture

```
+-------------------------------------------------+
|             hermes-suite container              |
|                                                 |
|  +-- supervisord (PID 1) --------------------+  |
|  |                                           |  |
|  |  [hermes-gateway]   port 8642             |  |
|  |    hermes gateway run                     |  |
|  |                                           |  |
|  |  [hermes-dashboard] port 9119             |  |
|  |    hermes dashboard --host 0.0.0.0        |  |
|  |                                           |  |
|  |  [hermes-webui]     port 8787             |  |
|  |    python server.py                       |  |
|  |                                           |  |
|  +-------------------------------------------+  |
|                                                 |
|  /opt/data  <-- mounted from ~/.hermes          |
+-------------------------------------------------+
```

## Prerequisites

- Podman v3.4.4+ or Docker
- podman-compose (or docker-compose)
- ~10GB disk space for the image
- Network access during build (for git clone and pip install)
- Works on both amd64 (x86_64) and arm64 (ARMv8) — tested on Jetson Orin NX

## Version Management

To ensure stability on edge devices (Jetson, ARM boards), it is highly recommended
to use **pinned versions** rather than building from `latest` or `master`.

### Using Pre-Built Images (Recommended)

If you prefer not to build manually, use our pre-verified image tags from
[Docker Hub](https://hub.docker.com/r/ascensionoid/hermes-suite):

```bash
podman pull ascensionoid/hermes-suite:2026.4.30-0.50.255
```

### Manual Build with Specific Versions

If you need a specific combination, pass the versions as build arguments:

```bash
podman build \
  --build-arg AGENT_VERSION=v2026.4.30 \
  --build-arg HERMES_WEBUI_VERSION=v0.50.255 \
  -t hermes-suite:2026.4.30-0.50.255 .
```

Or use the build helper (reads from `versions.env`):

```bash
./build.sh
# Override defaults:
# ./build.sh --agent v2026.4.30 --webui v0.50.255
```

### Version Compatibility Table

Every release is an explicitly tested pair of Agent + WebUI on both amd64 and arm64.

| Suite Tag | Agent Version | WebUI Version | Tested |
|-----------|--------------|---------------|--------|
| `2026.4.30-0.50.255` | v2026.4.30 | v0.50.255 | amd64 + arm64 |
| `2026.4.23-0.50.156` | v2026.4.23 | v0.50.156 | amd64 + arm64 |

### Version Tag Format

Suite tags follow the pattern `{agent_date}-{webui_semver}`:
- **Agent**: date-based version from `nousresearch/hermes-agent` (e.g. `v2026.4.30`)
- **WebUI**: semantic version from `nesquena/hermes-webui` (e.g. `v0.50.255`)

The pinned pair for each release is declared in `versions.env`.

## Quick Start

### 1. Clone this repo

```bash
git clone https://github.com/sunnysktsang/hermes-suite.git
cd hermes-suite
```

### 2. Build the image

```bash
chmod +x *.sh
./build.sh
```

Or manually with pinned versions:

```bash
podman build \
  --build-arg AGENT_VERSION=v2026.4.30 \
  --build-arg HERMES_WEBUI_VERSION=v0.50.255 \
  -t ascensionoid/hermes-suite:2026.4.30-0.50.255 .
```

### 3. Create the network (if not already existing)

```bash
podman network create --subnet 10.99.0.0/24 agent_net
```

### 4. Start the container

```bash
./up.sh
```

Or manually:

```bash
podman-compose up -d
```

### 5. Configure

Edit `~/.hermes/.env` to add your API keys, and `~/.hermes/config.yaml` for model settings.
These files are shared from the host via the volume mount. On first run, defaults are
created automatically from the hermes-agent examples.

### 6. Access

- Gateway:   http://localhost:8642
- WebUI:     http://localhost:8787
- Dashboard: http://localhost:9119

## Configuration

All configuration is stored in `~/.hermes/` on the host (mounted as `/opt/data` inside
the container). On first start, the entrypoint script copies default `.env` and
`config.yaml` from the hermes-agent examples if they don't already exist.

```
~/.hermes/
  .env            — API keys (OPENAI_API_KEY, TELEGRAM_TOKEN, etc.)
  config.yaml     — Model, toolsets, agent settings
  SOUL.md         — Agent personality
  skills/         — Custom skills
  memories/       — Persistent memory
  webui/          — WebUI state (sessions, workspace)
```

## Stopping

```bash
./down.sh
```

## Viewing Logs

```bash
./logs.sh
```

All service logs stream to stdout/stderr (visible via `podman logs`). Supervisord
also writes to `/var/log/supervisor/` inside the container:

```bash
podman exec hermes-suite supervisorctl status
```

## Customization

### Changing component versions

Edit `versions.env` to change the pinned versions:

```
AGENT_VERSION=v2026.4.30
WEBUI_VERSION=v0.50.255
```

Then rebuild:

```bash
./build.sh
```

Or override at build time:

```bash
./build.sh --agent v2026.4.16 --webui v0.50.244
```

### Changing the workspace path

Edit the `volumes` section in `docker-compose.yaml`:

```yaml
volumes:
  - ~/workspace:/workspace:z   # change ~/workspace to your project directory
```

## Migration from Multi-Container Setup

If you are currently running the multi-container setup (hermes-agent + hermes-webui):

1. Stop the existing containers.

2. Build and start hermes-suite:
   ```bash
   cd hermes-suite
   ./build.sh
   ./up.sh
   ```

3. Your existing `~/.hermes/` data is reused automatically — no migration needed.

## Troubleshooting

### Permission errors on ~/.hermes

Ensure the directory is owned by your user:

```bash
sudo chown -R $(id -u):$(id -g) ~/.hermes
```

### WebUI not loading

Check that the webui venv was built correctly:

```bash
podman exec hermes-suite /opt/hermes-webui/venv/bin/python -c "import yaml; print('OK')"
```

### Services fail with "EACCES making dispatchers"

Supervisord cannot open `/dev/stdout` when a TTY is allocated (it becomes a PTY slave).
Do NOT add `tty: true` to docker-compose.yaml — the container runs correctly without it.

### Dashboard returns connection error

The dashboard needs the gateway running first. Check supervisord status:

```bash
podman exec hermes-suite supervisorctl status
```

### Build fails on git clone

Ensure the build host has network access. The hermes-webui repo is cloned at build
time. If your build environment has no internet, pre-clone the webui repo and adjust
the Dockerfile to `COPY` it instead of `git clone`.

### Build fails on `uv venv` or `pip not found`

The Dockerfile uses `uv` (pre-installed in the hermes-agent base image) to create
virtual environments and install packages. If you change the base image, ensure `uv`
is available at `/usr/local/bin/uv`.

## How It Works

The Dockerfile performs these steps:

1. **Base image** — Uses the official `nousresearch/hermes-agent` image which already
   contains Python 3.13, Node.js, npm, Playwright, the agent code, and the built-in
   dashboard.

2. **System packages** — Installs sudo, git, nano, network tools, and other utilities.

3. **Tinker-Atropos** — Installs the optional reasoning engine from the agent source.

4. **Browser tools** — Installs Playwright Chromium for the browser toolset.

5. **Supervisor** — Installs supervisord via pip into a dedicated venv at `/opt/supervisor`
   (not available in Debian Trixie apt repos).

6. **Hermes WebUI** — Clones from GitHub and installs into a separate venv at
   `/opt/hermes-webui/venv`, along with the agent's Python dependencies so the WebUI
   can import agent modules.

7. **Entrypoint** — `start.sh` handles UID/GID remapping (for rootless Podman),
   directory setup, and config bootstrapping before launching supervisord.

## Files

```
hermes-suite/
  Dockerfile           — Build definition (parameterized AGENT_VERSION + HERMES_WEBUI_VERSION)
  versions.env         — Pinned component versions for current release
  supervisord.conf     — Process manager config (3 services)
  start.sh             — Container entrypoint (UID setup + launch)
  docker-compose.yaml  — Podman/Docker Compose configuration
  build.sh             — Build helper script (reads versions.env)
  up.sh                — Start helper script
  down.sh              — Stop helper script
  logs.sh              — Log viewer helper script
  .dockerignore        — Build context exclusions
  .env.example         — Environment variable template
  README.md            — This file
```

## Tested On

| Platform | Arch | OS | Runtime | Status |
|----------|------|----|---------|--------|
| x86_64 (WSL2) | amd64 | Ubuntu 22.04 | Podman 3.4.4 | All 3 services running |
| Jetson Orin NX 16GB | arm64 | Ubuntu 22.04 | Podman 3.4.4 | All 3 services running |

The base image `nousresearch/hermes-agent` provides multi-architecture manifests (amd64 + arm64).
Podman and Docker automatically pull the correct variant for your platform.
No changes to the Dockerfile are needed — it builds identically on both architectures.

## License

This project is provided as-is. The individual components are licensed separately:
- [hermes-agent](https://github.com/NousResearch/hermes-agent) — by Nous Research
- [hermes-webui](https://github.com/nesquena/hermes-webui) — by nesquena (MIT)

---

> If this project helps you, consider giving it a ⭐ on [GitHub](https://github.com/sunnysktsang/hermes-suite) — it helps others find it and keeps the project maintained.
