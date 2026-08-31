# Setup guide — initialize Docker Compose and authenticate Orca Server

This guide walks you from a clean machine to a **paired** headless Orca Server
on the Tailnet. Everything is in English. Secrets stay in `.env` (gitignored)
and on Docker volumes — never commit them.

Related docs:

- [README.md](../README.md) — overview
- [OPERATIONS.md](OPERATIONS.md) — day-2 ops (mup, accounts, ports)
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) — full architecture/spec

---

## 0. What you will end up with

```text
Your laptop (Orca Desktop)
        │
     Tailscale
        │
┌───────▼────────────────┐
│ Docker host            │
│  ├─ orca-tailscale     │  MagicDNS: orca-dev
│  └─ orca-server        │  ws://orca-dev:6768  (shared netns)
│       HOME volume      │  Orca binary + pair state + agent creds
│       /workspace       │  git repos
└────────────────────────┘
```

Authentication has **two layers**:

| Layer | What it does | How |
|-------|----------------|-----|
| **1. Pair Desktop ↔ Server** | Trust + E2EE channel to the remote Orca | `orca://pair?code=…` URL from logs |
| **2. Agent accounts** | Claude / Codex / etc. API credentials **on the server** | Desktop UI or native CLI inside the container |

Layer 1 is required before remote work. Layer 2 is required before agents can call providers.

---

## 1. Prerequisites

### On the Docker host (server)

- Linux with Docker Engine + **Compose v2** (`docker compose version`)
- `/dev/net/tun` available (needed by the Tailscale sidecar)
- Outbound HTTPS (download Orca AppImage ~200 MB on first boot if not seeded)
- Enough disk for image + volume (plan ~2–4 GB free)

```bash
docker --version
docker compose version
ls -l /dev/net/tun
```

### On the client (your laptop/desktop)

- [Orca Desktop](https://www.onorca.dev/) installed
- Same **Tailscale tailnet** as the server (install Tailscale and log in)
- Ability to open `orca://` links or paste a pairing URL

### Tailscale admin

Create a **reusable or one-off auth key** for the sidecar:

1. Open the Tailscale admin console → **Settings** → **Keys**
2. Generate an **auth key** (prefer tagged/ephemeral policies that fit your org)
3. Copy the value (looks like `tskey-auth-…`) — you will put it only in `.env`

Do **not** paste the key into git, screenshots, or public chats.

---

## 2. Get the repository

```bash
git clone https://github.com/chameleonbr/orca-server.git
cd orca-server
```

(Private repo: authenticate with `gh auth login` or a deploy key first.)

---

## 3. Create and edit `.env`

```bash
cp .env.example .env
```

Edit `.env` with a text editor. **Minimum required values:**

```text
# --- required for pairing / Tailnet ---
TS_AUTHKEY=tskey-auth-xxxxxxxx
TAILSCALE_HOSTNAME=orca-dev
ORCA_PAIRING_ADDRESS=orca-dev

# --- git identity inside the container (applied on every boot) ---
GIT_USER_NAME=John Doe
GIT_USER_EMAIL=john@doe.com
GIT_INIT_DEFAULT_BRANCH=main

# --- recommended ---
ORCA_PORT=6768
ORCA_VERSION=latest
TZ=America/Sao_Paulo
MUP_SCHEDULE=true
MUP_CRON=15 4 * * *
MUP_ON_BOOT=false
```

### Field notes

| Variable | Rules |
|----------|--------|
| `TS_AUTHKEY` | From Tailscale admin. Required for the sidecar to join the tailnet. |
| `TAILSCALE_HOSTNAME` | Node name on the tailnet (default `orca-dev`). Must be unique on your tailnet. |
| `ORCA_PAIRING_ADDRESS` | Host/IP **advertised** in the pairing offer. Use the MagicDNS name (`orca-dev`) or the Tailscale IP (`100.x.y.z`). **Never** `0.0.0.0`, `*`, or `::` — Orca rejects wildcards. |
| `GIT_USER_*` | Written to `~/.gitconfig` on the volume at boot. |
| `INSTALL_*` | Which agent CLIs to install at build / `mup` time. |

Confirm `.env` is ignored:

```bash
git check-ignore -v .env
# expect: .gitignore:…  .env
```

---

## 4. Build the image

```bash
docker compose build
```

This builds `orca-server:local` (Debian Slim, mise, scripts, optional agent installers).  
The **Orca AppImage is not baked in by default** — it downloads into the volume on first start.

Build args of interest (already wired from `.env`):

- `ORCA_SEED_IN_IMAGE=true` — optional: embed a seed copy at build (still updatable on the volume)
- `INSTALL_CLAUDE` / `INSTALL_CODEX` / … — toggle agents at image build

---

## 5. Start the stack

```bash
docker compose up -d
docker compose ps
```

Expected services:

| Container | Role | Health |
|-----------|------|--------|
| `orca-tailscale` | Tailscale sidecar, owns the network namespace | healthy |
| `orca-server` | Orca + mise + agents (`network_mode: service:tailscale`) | healthy |

First boot notes:

1. Tailscale must become **healthy** before Orca starts (`depends_on` condition).
2. If the volume has no Orca yet, the entrypoint downloads and extracts the AppImage (~200 MB) into `orca-home`.
3. `GIT_USER_NAME` / `GIT_USER_EMAIL` are applied into `~/.gitconfig` on the volume.

Follow logs:

```bash
docker compose logs -f tailscale
docker compose logs -f orca
```

---

## 6. Verify Tailscale and Orca are ready

### 6.1 Tailscale node

On any machine already on the same tailnet (or via admin console):

```bash
# on a Tailscale client
tailscale status | grep orca-dev
```

You should see the hostname (`orca-dev` by default) and a `100.x.y.z` address.

From the host:

```bash
docker compose exec tailscale tailscale status
docker compose exec tailscale tailscale ip -4
```

### 6.2 Orca server ready

```bash
docker compose logs orca 2>&1 | grep -E 'Orca server ready|Bound endpoint|Advertised endpoint|Pairing URL'
```

Healthy log pattern:

```text
Orca server ready
Bound endpoint: ws://0.0.0.0:6768
Advertised endpoint: ws://orca-dev:6768
Pairing URL: orca://pair?code=...
```

Doctor (optional but recommended):

```bash
docker compose exec orca /scripts/doctor.sh
docker compose exec orca /scripts/update-orca.sh --status
```

### 6.3 Reachability from the client

On the **client** laptop (same tailnet):

```bash
# MagicDNS
ping -c 2 orca-dev
# or Tailscale IP from `tailscale status`
nc -vz orca-dev 6768
# or:  nc -vz 100.x.y.z 6768
```

Port `6768` must be reachable **only** on the Tailnet. Compose does **not** publish it on the host public interface by default.

---

## 7. Authenticate the Orca Server (Desktop pairing)

This is the **server authentication** step: your Desktop becomes a trusted client of the remote headless Orca.

### 7.1 Copy the Pairing URL

```bash
docker compose logs orca 2>&1 | grep 'Pairing URL'
```

Copy the full line value, for example:

```text
orca://pair?code=eyJ...
```

What is inside the code (informational): a **v2 pairing offer** JSON (Base64URL) containing:

- `endpoint` — advertised WebSocket URL (`ws://orca-dev:6768`)
- `deviceToken` — one-time device token
- `publicKeyB64` — Curve25519 key material for E2EE
- `scope` — typically `runtime` for Desktop remote servers

You do **not** need to decode it manually.

### 7.2 Add the server in Orca Desktop

On the client machine (same Tailnet as `orca-dev`):

1. Open **Orca Desktop**
2. Go to **Settings → Remote Orca Servers** (wording may be “Add remote server” / “Environments”)
3. Choose **Add** / paste pairing URL
4. Paste the `orca://pair?code=…` value
5. Confirm / trust the device when prompted

CLI alternative on a machine that has the Orca CLI and can reach the endpoint:

```bash
orca environment add
# paste the pairing URL when prompted
orca environment list
```

### 7.3 Confirm pair succeeded

In Desktop:

- The remote server appears in the environment / remote server list
- You can open a remote session / workspace against it

On the server, pairing state is stored under the **orca-home** volume
(`~/.config/orca` / related paths). Restarts keep the pair; replacing the
AppImage with `update-orca` does **not** wipe pairing state.

### 7.4 If pairing fails

| Symptom | Check |
|---------|--------|
| Timeout / cannot connect | Client not on same tailnet; `nc -vz orca-dev 6768` fails |
| Invalid endpoint | `ORCA_PAIRING_ADDRESS` was `0.0.0.0` or empty — set to `orca-dev` or Tailscale IP, recreate container |
| Stale pairing URL | Restart Orca and copy a **fresh** Pairing URL from logs |
| Auth key / Tailscale down | `docker compose logs tailscale`; regenerate `TS_AUTHKEY` if needed |
| Advertised host unknown on client | MagicDNS off, or typo in hostname — use Tailscale IP in `ORCA_PAIRING_ADDRESS` and recreate |

Recreate after fixing `.env`:

```bash
docker compose up -d --force-recreate orca
docker compose logs -f orca
```

---

## 8. Authenticate AI agents (after pair)

Pairing alone does **not** log into Claude/Codex. Add provider accounts **on the server**.

### Option A — Orca Desktop (recommended)

With the remote environment selected, add managed accounts (Claude, Codex, …)
through the Orca UI so credentials live on the remote host volume.

### Option B — Native CLI inside the container

```bash
docker compose exec -it orca bash

claude          # Anthropic login flow
codex login     # OpenAI login flow
gemini          # Google login flow
opencode        # per OpenCode docs
```

Credentials persist on the `orca-home` volume (`~/.claude`, `~/.codex`, …).

### Option C — `orca account` CLI (serve must be stopped)

While `orca serve` is running, a second Orca process hits the **Electron
single-instance lock**. Only use this path if you stop serve first:

```bash
docker compose stop orca
docker compose run --rm --entrypoint /scripts/entrypoint.sh orca \
  orca account add --agent claude
docker compose up -d orca
```

Prefer A or B for day-to-day use.

Details: [OPERATIONS.md](OPERATIONS.md).

---

## 9. Smoke checks after auth

```bash
# stack
docker compose ps

# versions
docker compose exec orca /scripts/versions.sh
docker compose exec orca /scripts/doctor.sh

# git identity from env
docker compose exec orca git config --global --get user.name
docker compose exec orca git config --global --get user.email
```

From Desktop: open a remote workspace and run a simple agent prompt.

Optional dynamic-port check (any process bound to `0.0.0.0` is reachable on the Tailnet):

```bash
docker compose exec orca python3 -m http.server 9123 --bind 0.0.0.0
# on client: open http://orca-dev:9123
```

---

## 10. Day-2 essentials

```bash
# update tools + Orca + agents (no image rebuild)
docker compose exec orca mup

# Orca only
docker compose exec orca update-orca latest
# supervisor recycles the process when the binary changes

# stop / start
docker compose stop
docker compose up -d

# full wipe (DESTROYS pair state and agent creds)
docker compose down -v
```

Scheduled `mup` runs **inside** the container (supercronic). Nothing is installed
on the host cron/systemd.

---

## 11. Local smoke without Tailscale (optional)

For image/script testing only, use the local compose file (publishes a host port;
not for production pairing over Tailnet):

```bash
docker compose -f docker-compose.local.yml up -d --build
```

Production / real pairing uses `docker-compose.yml` + Tailscale as in steps 3–7.

---

## 12. Security checklist

- [ ] `.env` never committed; `TS_AUTHKEY` rotated if leaked
- [ ] No host publish of `6768` in production compose
- [ ] `ORCA_PAIRING_ADDRESS` is a Tailnet name/IP, not a public wildcard
- [ ] Orca runs as non-root user `orca`
- [ ] No `--privileged` / no FUSE for Orca
- [ ] Docker socket only via optional profile `docker-access` (elevated risk)
- [ ] Backups of `orca-home` treated as secret material (encrypt)

---

## Quick reference — copy/paste

```bash
# 1) config
cp .env.example .env
# edit TS_AUTHKEY, ORCA_PAIRING_ADDRESS=orca-dev, GIT_USER_*

# 2) build & start
docker compose build
docker compose up -d
docker compose ps
docker compose logs -f orca

# 3) pair
docker compose logs orca 2>&1 | grep 'Pairing URL'
# Desktop → Settings → Remote Orca Servers → paste URL

# 4) agents
docker compose exec -it orca bash
# claude / codex login / gemini / opencode
```

---

## Checklist — first successful auth

| Step | Done when |
|------|-----------|
| `.env` filled | `TS_AUTHKEY`, `ORCA_PAIRING_ADDRESS`, git identity set |
| `docker compose up -d` | `orca-tailscale` + `orca-server` **healthy** |
| Tailnet | `orca-dev` visible; `nc -vz orca-dev 6768` OK from client |
| Logs | `Orca server ready` + `Pairing URL: orca://pair?code=…` |
| Desktop pair | Remote server listed and session opens |
| Agent login | At least one provider account works on a remote prompt |
