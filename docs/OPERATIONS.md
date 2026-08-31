# Operations — orca-server

Everything runs **inside the container**. The host only runs `docker compose up/down`.

**First boot / pair Orca Server from scratch?** Use **[SETUP.md](SETUP.md)**  
(Docker Compose init, `.env`, Tailscale, Desktop pairing, agent login).

## Current status (A–E + pair)

| Item | State |
|------|--------|
| Tailscale node | `orca-dev` (MagicDNS) |
| Orca | volume `~/.local/share/orca`, upgrade without rebuild |
| mup | supercronic 04:15 `America/Sao_Paulo` |
| Agents on volume | claude, codex, gemini, opencode |
| Pairing | via `orca://pair?code=…` in Desktop |

## Pairing (validated)

1. Client on the same Tailnet.
2. Logs:
   ```bash
   docker compose logs orca 2>&1 | grep 'Pairing URL'
   ```
3. Desktop: Settings → Remote Orca Servers → paste URL.
4. Advertised endpoint: `ws://orca-dev:6768` (real bind `0.0.0.0:6768`).

The link is a **v2 offer** (endpoint + deviceToken + publicKey) in Base64URL.

## Agent accounts (next operational step)

The CLI `orca account *` **cannot** start a second process while `orca serve` is running
(Electron single-instance lock on the same `userData`). Prefer:

### A) Orca Desktop (recommended after pair)

On the paired remote runtime: add Claude/Codex accounts via the Orca UI
(managed accounts on the host).

### B) Native login in the container (credentials on the HOME volume)

```bash
docker compose exec orca bash
# PATH already includes ~/.local/bin + mise shims

claude          # or: claude auth login
codex login     # official OpenAI flow
gemini          # Google auth per CLI
opencode        # auth per CLI
```

Credentials live under `~/.claude`, `~/.codex`, etc. on the **orca-home** volume — they survive restarts and `mup`.

### C) Via Orca CLI (only if serve is stopped)

```bash
docker compose stop orca
docker compose run --rm --entrypoint /scripts/entrypoint.sh orca orca account add --agent claude
# … then compose start again
```

In practice, **A or B** are better.

## Update without rebuild

```bash
docker compose exec orca mup                 # tools + agents (+ orca if MUP_ORCA)
docker compose exec orca mise run agents:update
docker compose exec orca update-orca latest  # supervisor recycles if binary changed
docker compose exec orca /scripts/doctor.sh
```

## Dynamic ports (Tailnet)

No host publish. Any process in the container listening on `0.0.0.0:<port>`
is reachable as `http://orca-dev:<port>` on the Tailnet.

Manual test:

```bash
docker compose exec orca python3 -m http.server 9123 --bind 0.0.0.0
# on another Tailnet device: http://orca-dev:9123
```

## Phase H — hardening + dynamic ports (validated)

Recorded on host stack (`orca-dev` / `100.78.39.19`).

### Dynamic ports (§88)

No Compose port publish. Two ephemeral servers inside the container:

| Bind | From Tailnet client | Result |
|------|---------------------|--------|
| `0.0.0.0:9123` | `http://100.78.39.19:9123` | **HTTP 200** |
| `0.0.0.0:9876` | `http://100.78.39.19:9876` | **HTTP 200** |
| `0.0.0.0:9123` | `http://orca-dev:9123` (MagicDNS) | **HTTP 200** |

Compose was **not** changed between ports — proves dynamic previews on the Tailnet.

### Security checklist

| Check | Result |
|-------|--------|
| Host `ports:` published | **none** in rendered compose |
| `--privileged` / docker.sock default | **absent** |
| Process user | `uid=1000(orca)` |
| `.env` in git | **ignored** |
| Orca FUSE / privileged | **not used** |
| Access path | Tailnet only (`orca-dev`) |

### Update-without-rebuild (related)

`mup` (post symlink fix `60b898b`): tools + Orca + agents **failures=0**, no image rebuild.

### Residual (non-blocking)

- dbus / X11 software bitmap noise in headless logs — expected
- Agent provider logins = **Phase F** (run inside Orca shell / Desktop UI)

## Phase G — optional agents (validated)

Installed on volume via `update-agents` / `mup` (no image rebuild):

| Agent | Binary | Source | Version seen |
|-------|--------|--------|--------------|
| Cursor Agent | `agent` / `cursor-agent` | https://cursor.com/install | 2026.08.25-3e8eec8 |
| Grok | `grok` | npm `@xai-official/grok` | 1.0.13 |
| Hermes | `hermes` | PyPI `hermes-agent` | 0.19.0 |
| Qwen Code | `qwen` | npm `@qwen-code/qwen-code` | 0.22.3 |
| Kimi | `kimi` | npm `@moonshot-ai/kimi-code` | 0.39.1 |

Flags (default **off** — opt in via `.env`):

```text
INSTALL_CURSOR=true
INSTALL_GROK=false
INSTALL_HERMES=false
INSTALL_QWEN=false
INSTALL_KIMI=false
CURSOR_INSTALL_URL=https://cursor.com/install
```

Enable one or more, then:

```bash
docker compose exec -e INSTALL_GROK=true -e INSTALL_QWEN=true orca /scripts/update-agents.sh
# or set flags in .env and:
docker compose exec orca mup
```

## Sensitive files

- `.env` (`TS_AUTHKEY`) — gitignored, never commit
- volume `orca-home` — pairing state + agent creds (encrypted backup)

## Useful commands

```bash
docker compose ps
docker compose logs -f orca
docker compose exec orca /scripts/update-orca.sh --status
docker compose exec orca mise run agents:versions
tailscale status | grep orca-dev   # on the host
```
