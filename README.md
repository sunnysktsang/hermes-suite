# Hermes Suite — All-in-One Container Image
![Docker Pulls](https://badgen.net/docker/pulls/ascensionoid/hermes-suite)

Single Docker/Podman image combining three Hermes services:

| Service | Port | Description |
|---------|------|-------------|
| hermes-gateway | 8642 | Agent gateway (CLI, Telegram, cron, tools) |
| hermes-dashboard | 9119 | Monitoring/analytics dashboard (built-in) |
| hermes-webui | 8787 | Browser-based chat interface |

Pre-built multi-arch images available on [Docker Hub](https://hub.docker.com/r/ascensionoid/hermes-suite?ref=2).

> **🎉 Now with automatic runtime detection.** One image works on both Podman and Docker CE out of the box — no separate builds or flags needed. The container detects its runtime at startup and adjusts automatically. [Learn more](#changing-component-versions).

🏗️ Official container images are maintained by Ascensionoid ([ascensionoid.com](https://ascensionoid.com)).

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
to use **pinned versions** rather than building from the `main` branch HEAD.

### Using Pre-Built Images (Recommended)

If you prefer not to build manually, use our pre-verified image tags from
[Docker Hub](https://hub.docker.com/r/ascensionoid/hermes-suite):

```bash
podman pull ascensionoid/hermes-suite:2026.7.1-0.51.882
```

### Manual Build with Specific Versions

If you need a specific combination, pass the versions as build arguments:

```bash
podman build \
  --build-arg AGENT_VERSION=v2026.7.1 \
  --build-arg HERMES_WEBUI_VERSION=v0.51.882 \
  -t hermes-suite:2026.7.1-0.51.882 .
```

Or use the build helper (reads from `versions.env`):

```bash
# Podman or Docker (auto-detected at container startup)
./build.sh

# Build with Docker explicitly
./build.sh --docker

# Docker without logs (optional)
./build.sh --docker-nolog

# Override defaults:
# ./build.sh --agent v2026.7.1 --webui v0.51.882
```

> **Docker compatibility:** Docker CE is auto-detected at container startup via /proc/1/cgroup.
> The universal image works on both Podman and Docker out of the box.
> Use `--docker-nolog` only if you prefer no log output.
> Set CONTAINER_RUNTIME in versions.env to control which runtime helper scripts use.

### Version Compatibility Table

Every release is an explicitly tested pair of Agent + WebUI on both amd64 and arm64.

| Suite Tag | Agent Version | WebUI Version | Tested |
|-----------|---------------|---------------|--------|
| `2026.7.1-0.51.882` | v2026.7.1 | v0.51.882 | amd64 + arm64 |

> **Full version history:** https://github.com/sunnysktsang/hermes-suite/releases

### Version Tag Format

Suite tags follow the pattern `{agent_date}-{webui_semver}`:
- **Agent**: date-based version from `nousresearch/hermes-agent` (e.g. `v2026.7.1`)
- **WebUI**: semantic version from `nesquena/hermes-webui` (e.g. `v0.51.882`)

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
  --build-arg AGENT_VERSION=v2026.7.1 \
  --build-arg HERMES_WEBUI_VERSION=v0.51.882 \
  -t ascensionoid/hermes-suite:2026.7.1-0.51.882 .
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
- Dashboard: http://localhost:9119 (login: admin/admin by default — see [Dashboard Authentication](#dashboard-authentication))

### Dashboard Authentication

Since hermes-agent v2026.7.1, the dashboard requires authentication to access
on a non-loopback bind. Hermes Suite provides this via the `DASHBOARD_CREDENTIAL`
setting in `versions.env`:

```env
# Default - works immediately, no setup needed:
DASHBOARD_CREDENTIAL=admin:admin

# Auto-generate a random password (printed by up.sh on first start):
DASHBOARD_CREDENTIAL=auto

# Use your own credentials:
DASHBOARD_CREDENTIAL=myuser:mypassword
```

The credential is displayed in the `up.sh` output when the container starts:

```
Hermes Suite is running:
  Gateway:    http://localhost:8642
  WebUI:      http://localhost:8787
  Dashboard:  http://localhost:9119

  Dashboard Login ID: admin
  Dashboard Password: admin
```

When set to `auto`, a random password is generated once and persisted to
`.dashboard_credential` (in the repo directory) so it survives container restarts.

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

Edit `versions.env` to change the pinned versions and runtime settings:

```env
AGENT_VERSION=v2026.7.1
WEBUI_VERSION=v0.51.882

# Runtime selector: auto (default), podman, docker, docker-nolog
CONTAINER_RUNTIME=auto

# Use sudo for commands (rootful mode): true, false
USE_SUDO=false

# Dashboard login: "username:password", "auto", or "admin:admin" (default)
DASHBOARD_CREDENTIAL=admin:admin

# Include WhatsApp bridge: true, false (default: false)
ENABLE_WHATSAPP_BRIDGE=false
```

| Setting | Options | Default | Description |
|---------|---------|---------|-------------|
| `CONTAINER_RUNTIME` | `auto`, `podman`, `docker`, `docker-nolog` | `auto` | Which runtime helper scripts use. `auto` detects at script time. |
| `USE_SUDO` | `true`, `false` | `false` | Run docker/podman commands with sudo (rootful mode) |
| `DASHBOARD_CREDENTIAL` | `admin:admin`, `auto`, `user:pass` | `admin:admin` | Dashboard login credential |
| `ENABLE_WHATSAPP_BRIDGE` | `true`, `false` | `false` | Include WhatsApp bridge in the built image |

Then rebuild:

```bash
./build.sh
```

Or override at build time:

```bash
./build.sh --agent v2026.4.16 --webui v0.50.244
```

### WhatsApp Bridge

The WhatsApp bridge is **not included** in the image by default. This is intentional:

- The bridge uses [Baileys](https://github.com/WhiskeySockets/Baileys) to emulate a WhatsApp Web session
- Without proper configuration, **anyone who messages your number gets full agent access** (terminal, filesystem, browser)
- See [upstream issue #15108](https://github.com/NousResearch/hermes-agent/issues/15108) for details

To include the WhatsApp bridge at build time:

```bash
# Option 1: CLI flag
./build.sh --whatsapp

# Option 2: Set in versions.env
ENABLE_WHATSAPP_BRIDGE=true
./build.sh
```

> **Warning:** If you enable the WhatsApp bridge, you **must** configure `WHATSAPP_ALLOWED_USERS`
> in `~/.hermes/.env` before starting the gateway. Without this setting, the bridge denies all
> incoming messages by default.

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

**Rootless Podman:**

The container runs as UID 10000, which maps to a host UID (e.g. 109999) per `/etc/subuid`.
Fix ownership on the host:

```bash
sudo chown -R 109999:109999 ~/.hermes
```

**Rootful Podman or Docker:**

Ownership is auto-corrected on startup. If issues persist:

```bash
sudo chown -R 10000:10000 ~/.hermes
```

### WebUI not loading

Check that the webui venv was built correctly:

```bash
podman exec hermes-suite /opt/hermes-webui/venv/bin/python -c "import yaml; print('OK')"
```

### Services fail with "EACCES making dispatchers" (Docker only)

This should not occur with the auto-detection feature (v2026.5.16-0.51.137+).
The container detects Docker at startup and adjusts the privilege model automatically.
Ensure you are using a recent image.

If it still occurs, ensure `tty: true` is NOT set in docker-compose.yaml.

### Dashboard returns connection error

The dashboard needs the gateway running first. Check supervisord status:

```bash
podman exec hermes-suite supervisorctl status
```

### Dashboard asks for a login

Since hermes-agent v2026.7.1, the dashboard requires authentication. The default
credential is `admin:admin` (configured in `versions.env`). To change it, see
[Dashboard Authentication](#dashboard-authentication).

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

3. **Browser tools** — Installs Playwright Chromium for the browser toolset.

4. **Supervisor** — Installs supervisord via pip into a dedicated venv at `/opt/supervisor`
   (not available in Debian Trixie apt repos).

5. **Hermes WebUI** — Clones from GitHub and installs into a separate venv at
   `/opt/hermes-webui/venv`, along with the agent's Python dependencies so the WebUI
   can import agent modules.

6. **Entrypoint** — `start.sh` handles UID/GID remapping (for rootless Podman),
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
| x86_64 (WSL2) | amd64 | Ubuntu 22.04 | Docker CE 29.4.2 | All 3 services running |
| Jetson Orin NX 16GB | arm64 | Ubuntu 22.04 | Podman 3.4.4 | All 3 services running |

The base image `nousresearch/hermes-agent` provides multi-architecture manifests (amd64 + arm64).
Podman and Docker automatically pull the correct variant for your platform.
No changes to the Dockerfile are needed — it builds identically on both architectures.

## License

This project is licensed under the MIT License. The individual components are licensed separately:
- [hermes-agent](https://github.com/NousResearch/hermes-agent) — by Nous Research (MIT)
- [hermes-webui](https://github.com/nesquena/hermes-webui) — by nesquena (MIT)

Thanks to [nesquena](https://github.com/nesquena) for building hermes-webui and [referencing this project](https://github.com/nesquena/hermes-webui/blob/master/docs/docker.md) in the official Docker docs.

---

> If this project helps you, consider giving it a ⭐ on [GitHub](https://github.com/sunnysktsang/hermes-suite) — it helps others find it and keeps the project maintained.
<img src="https://hits.sh/github.com/sunnysktsang/hermes-suite.svg" width="0" height="0" style="display:none;">
