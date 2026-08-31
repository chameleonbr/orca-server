# orca-server

Remote development workstation with headless **Orca Server**, **mise**, AI agents, and private access via a **Tailscale sidecar**.

> Status: Phases A–E + **Desktop pair OK** on host `dhh` (`orca-dev`). Next: agent accounts on the remote runtime.

**First time here?** Follow the full walkthrough:

→ **[docs/SETUP.md](docs/SETUP.md)** — initialize Docker Compose, configure `.env`, start the stack, and authenticate (pair) Orca Server from Desktop.

Day-2 ops (mup, agent logins, ports): [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Post-pair — accounts

After pairing, authenticate agents **on the server** (credentials live on the volume):

- Orca Desktop UI on the paired remote runtime, or
- `docker compose exec orca bash` → `claude` / `codex login` / `gemini` / `opencode`

Details: [docs/OPERATIONS.md](docs/OPERATIONS.md) · full first-boot guide: [docs/SETUP.md](docs/SETUP.md).

## What it is

```text
Notebook/Desktop (Orca IDE)
        │
     Tailscale
        │
┌───────▼────────┐
│ orca-dev       │  ← node on the Tailnet
│ :6768 Orca     │
│ :3000/:5173/…  │  ← dynamic dev ports (not published on the host)
│ Debian Slim    │
│ mise + agents  │
│ /workspace     │
└────────────────┘
```

Features:

- Debian Slim (no Ubuntu / Alpine)
- Headless Orca (extracted AppImage, **no FUSE** / **no `--privileged`**)
- **Orca runtime on the HOME volume** — upgrade without rebuilding the image
- **`mup`** — one mise command to update tools + Orca + agents
- **Scheduling 100% in-container** (supercronic) — no host cron/systemd
- mise for Node/Python/uv and AI CLI updates without rebuild
- Tailscale sidecar + `network_mode: service:tailscale`
- Persistent HOME and workspace
- No Docker socket and no public exposure by default

## mup — update everything with one command

Everything runs **inside** the container. The host only starts compose.

```bash
docker compose exec orca mup
# or
docker compose exec orca mise run mup
```

| Component | How | Rebuild? |
|-----------|-----|----------|
| Node / Python / uv | `mise install` + `upgrade` | No |
| Orca AppImage | volume `~/.local/share/orca` | No |
| Claude / Codex / Gemini | `npm i -g` → `~/.local` | No |

### Automatic schedule (in-container)

The `entrypoint` starts a **supervisor** that:

1. starts **supercronic** with `MUP_CRON` (default `15 4 * * *` = 04:15)
2. runs Orca as a child process
3. if `mup` replaces the Orca binary, **recycles the process** on its own (flag on the volume)

```text
# .env — nothing on the host
MUP_SCHEDULE=true
MUP_CRON=15 4 * * *
MUP_ON_BOOT=false
TZ=America/Sao_Paulo
```

| Variable | Default | Effect |
|----------|---------|--------|
| `MUP_SCHEDULE` | `true` | in-container cron on/off |
| `MUP_CRON` | `15 4 * * *` | overnight schedule |
| `MUP_ON_BOOT` | `false` | run `mup` on start (delays first ready) |
| `TZ` | `America/Sao_Paulo` | cron timezone |

Schedule logs: `~/.local/state/orca-agent-manager/mup-cron.log` (on the volume).

## Orca updates without rebuild

Headless Orca **has no auto-updater** (desktop GUI only). So the AppImage is **not frozen into the image**:

| Layer | What it holds |
|-------|----------------|
| **Docker image** | Debian, Electron libs, mise, scripts, base agents |
| **Volume `orca-home`** | `~/.local/share/orca/` (extracted AppImage) + credentials + mise data + `~/.config` |

### Update Orca

```bash
# current version
docker compose exec orca /scripts/update-orca.sh --status
# or
docker compose exec orca mise run orca:status

# upgrade to latest (or pin: 1.4.192)
docker compose exec orca /scripts/update-orca.sh latest
# or
docker compose exec orca mise run orca:update

# apply the new binary
docker compose restart orca

# if something breaks — roll back to the previous extract
docker compose exec orca /scripts/update-orca.sh --rollback
docker compose restart orca
```

On first boot, if the volume has no Orca yet, the entrypoint downloads it (~200 MB) into the volume.

Optional `.env` knobs:

```text
ORCA_VERSION=latest          # or 1.4.192
AUTO_UPDATE_ORCA=false         # true = try update on every start
ORCA_SEED_IN_IMAGE=false     # true = bake a seed at build (still updatable on the volume)
```

Official binary source:

```text
https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage
```

State (pairing, projects) lives in `~/.config/{orca,Orca}` — **independent of the binary**. Replacing the AppImage does not drop the pair.

## Planned agents

| Agent | Default |
|-------|---------|
| Claude Code | on |
| OpenAI Codex CLI | on |
| Gemini CLI | on |
| Cursor CLI | on |
| OpenCode | on |
| Grok | off (until official install is confirmed) |
| Hermes | off |
| Qwen Code | off |
| Kimi | off |

## Requirements

- Docker + Docker Compose v2
- Linux host (recommended) with `/dev/net/tun` for Tailscale
- Scoped Tailscale auth key for the sidecar
- Orca Desktop on the client for pairing

## Quick start

> Step-by-step (env, Tailscale, pair, agent auth, troubleshooting):  
> **[docs/SETUP.md](docs/SETUP.md)**

```bash
cp .env.example .env
# edit: TS_AUTHKEY, ORCA_PAIRING_ADDRESS (Tailscale IP/hostname — do not use 0.0.0.0)
# edit: GIT_USER_NAME, GIT_USER_EMAIL

docker compose build
docker compose up -d
docker compose logs -f orca
```

Pairing in Orca Desktop:

```text
Settings → Remote Orca Servers → Add Server → paste pairing URL from the logs
```

Get the URL:

```bash
docker compose logs orca 2>&1 | grep 'Pairing URL'
```

Logs should look like:

```text
Orca server ready
Bound endpoint: ws://0.0.0.0:6768
Advertised endpoint: ws://orca-dev:6768
Pairing URL: orca://pair?code=...
```

Authenticate agents (after pair):

```bash
docker compose exec -it orca bash
claude
codex login
gemini
# Prefer Desktop UI or native CLI login while `orca serve` is running
# (`orca account *` is blocked by Electron single-instance lock)
```

Diagnostics:

```bash
docker compose exec orca /scripts/doctor.sh
docker compose exec orca /scripts/versions.sh
docker compose exec orca /scripts/ports.sh
docker compose exec orca mise run orca:status
docker compose exec orca mise run agents:doctor
```

## Configuration

See [`.env.example`](.env.example).

| Variable | Description |
|----------|-------------|
| `ORCA_VERSION` | Pinned tag or `latest` (default) |
| `ORCA_PORT` | Server port (default `6768`) |
| `ORCA_PAIRING_ADDRESS` | Host/IP advertised in pairing (Tailscale) |
| `MUP_SCHEDULE` | In-container cron (`true`) |
| `MUP_CRON` | Cron expression (`15 4 * * *`) |
| `MUP_ON_BOOT` | Run `mup` on container start (`false`) |
| `TZ` | Schedule timezone |
| `AUTO_UPDATE_ALL` | Boot mup alias (`false`) |
| `GIT_USER_NAME` | `git config user.name` on boot |
| `GIT_USER_EMAIL` | `git config user.email` on boot |
| `GIT_INIT_DEFAULT_BRANCH` | default `main` |
| `TS_AUTHKEY` | Tailscale auth key |
| `TAILSCALE_HOSTNAME` | MagicDNS name (default `orca-dev`) |
| `INSTALL_*` | Enable/disable each agent at build / mup |

## Volumes

| Volume | Path | Contents |
|--------|------|----------|
| `orca-home` | `/home/orca` | **Orca runtime**, credentials, mise, configs |
| `workspace` | `/workspace` | repositories and worktrees |
| `tailscale-state` | `/var/lib/tailscale` | Tailscale node identity |

**Do not version** `data/` or `.env`. Backups of `orca-home` contain secrets — encrypt them.

## Networking

- No ports published on the host by default
- Access via Tailnet: `http://orca-dev:6768`, `http://orca-dev:3000`, etc.
- Dev servers must listen on `0.0.0.0` (not only `127.0.0.1`)
- Optional: Tailscale Serve; **do not** use Funnel by default
- Profile `docker-access` for the socket (elevated risk)

## Security

- Non-root Orca process (`user: orca`)
- No `--privileged` for Orca
- No FUSE
- No Docker socket by default
- Secrets kept out of the image
- Orca port only on the Tailnet / private network

## Project layout

```text
orca-server/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── config/mise.toml          # tasks: mup, orca:*, agents:*
├── config/mup.crontab        # reference (real schedule via MUP_CRON)
├── docs/SETUP.md                 # first-boot + pair/auth walkthrough
├── docs/OPERATIONS.md            # day-2 ops
├── docs/IMPLEMENTATION_PLAN.md   # full spec
└── scripts/
    ├── entrypoint.sh
    ├── supervise.sh          # supercronic + orca child + recycle
    ├── mup.sh                # update-all orchestrator
    ├── update-orca.sh
    ├── update-agents.sh
    ├── install-supercronic.sh
    ├── lib-orca.sh
    ├── orca-wrapper.sh
    ├── install-agents.sh
    ├── doctor.sh
    ├── versions.sh
    └── ports.sh
```

## Implementation phases

See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) §90.

| Phase | Focus | Status |
|-------|-------|--------|
| A | Docker base (Debian Slim, Electron libs, user) | done |
| B | mise (Node, Python, uv) | done |
| C | Orca runtime on volume + update-orca | done |
| D | Tailscale sidecar + dynamic ports | **done** (pair OK) |
| E | Agents + **mup** + **in-container** schedule | **done** (claude/codex/gemini/opencode) |
| F | Host accounts + official Cursor | **in progress** (pair done → agent login) |
| G | Optional agents | pending |
| H | Final hardening + formal dynamic-port test | pending |

## Upgrade

```bash
# EVERYTHING (tools + Orca + agents) — no rebuild, 100% in-container
docker compose exec orca mup
# if the Orca binary changed, the supervisor recycles it

# Orca only
docker compose exec orca update-orca latest

# agents only
docker compose exec orca mise run agents:update

# base image / system libs (rare)
docker compose build --pull
docker compose up -d
```

## Troubleshooting

```bash
docker compose logs -f tailscale
docker compose logs -f orca
docker compose exec orca /scripts/doctor.sh
docker compose exec orca /scripts/update-orca.sh --status
docker compose exec orca /scripts/ports.sh
```

## License

Private — all rights reserved until otherwise stated.
