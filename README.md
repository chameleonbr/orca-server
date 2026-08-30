# orca-server

Workstation remota de desenvolvimento com **Orca Server** headless, **mise**, agentes de IA e acesso privado via **Tailscale sidecar**.

> Status: Fases A–E + **pair Desktop OK** no host `dhh` (`orca-dev`). Próximo: contas dos agents no runtime remoto.

## Pós-pair — accounts

Depois do pair, autentique os agents **no servidor** (credenciais no volume):

- UI do Orca Desktop no runtime remoto, ou
- `docker compose exec orca bash` → `claude` / `codex login` / `gemini` / `opencode`

Detalhes: [docs/OPERATIONS.md](docs/OPERATIONS.md).

## O que é

```text
Notebook/Desktop (Orca IDE)
        │
     Tailscale
        │
┌───────▼────────┐
│ orca-dev       │  ← nó na Tailnet
│ :6768 Orca     │
│ :3000/:5173/…  │  ← portas dinâmicas de dev (sem publicar no host)
│ Debian Slim    │
│ mise + agents  │
│ /workspace     │
└────────────────┘
```

Características:

- Debian Slim (sem Ubuntu/Alpine)
- Orca headless (AppImage extraído, **sem FUSE** / **sem `--privileged`**)
- **Orca runtime no volume HOME** — upgrade sem remontar a imagem
- **`mup`** — um comando mise para atualizar tools + Orca + agents
- **Agendamento 100% no container** (supercronic) — nada de cron/systemd no host
- mise para Node/Python/uv e atualização de AI CLIs sem rebuild
- Tailscale sidecar + `network_mode: service:tailscale`
- HOME e workspace persistentes
- Sem Docker socket e sem exposição pública por padrão

## mup — atualizar tudo num comando

Tudo roda **dentro** do container. O host só sobe o compose.

```bash
docker compose exec orca mup
# ou
docker compose exec orca mise run mup
```

| Componente | Como | Rebuild? |
|------------|------|----------|
| Node / Python / uv | `mise install` + `upgrade` | Não |
| Orca AppImage | volume `~/.local/share/orca` | Não |
| Claude / Codex / Gemini | `npm i -g` → `~/.local` | Não |

### Agenda automática (dentro do container)

O `entrypoint` sobe um **supervisor** que:

1. inicia **supercronic** com `MUP_CRON` (default `15 4 * * *` = 04:15)
2. sobe o Orca como filho
3. se o `mup` trocar o binário do Orca, **recicla o processo** sozinho (flag no volume)

```text
# .env — nada no host
MUP_SCHEDULE=true
MUP_CRON=15 4 * * *
MUP_ON_BOOT=false
TZ=America/Sao_Paulo
```

| Variável | Default | Efeito |
|----------|---------|--------|
| `MUP_SCHEDULE` | `true` | cron in-container on/off |
| `MUP_CRON` | `15 4 * * *` | madrugada |
| `MUP_ON_BOOT` | `false` | `mup` no start (atrasa o ready) |
| `TZ` | `America/Sao_Paulo` | fuso do cron |

Logs do schedule: `~/.local/state/orca-agent-manager/mup-cron.log` (no volume).

## Orca atualiza sem rebuild

O headless **não tem auto-updater** (só o desktop GUI). Por isso o AppImage **não fica “congelado” na imagem**:

| Camada | O que guarda |
|--------|----------------|
| **Imagem Docker** | Debian, libs Electron, mise, scripts, agentes base |
| **Volume `orca-home`** | `~/.local/share/orca/` (AppImage extraído) + credenciais + mise data + `~/.config` |

### Atualizar Orca

```bash
# ver versão atual
docker compose exec orca /scripts/update-orca.sh --status
# ou
docker compose exec orca mise run orca:status

# subir para latest (ou pin: 1.4.192)
docker compose exec orca /scripts/update-orca.sh latest
# ou
docker compose exec orca mise run orca:update

# aplicar o binário novo
docker compose restart orca

# se der ruim — volta a versão anterior extraída
docker compose exec orca /scripts/update-orca.sh --rollback
docker compose restart orca
```

No primeiro boot, se o volume ainda não tiver Orca, o entrypoint baixa sozinho (~200 MB) para o volume.

Opcional no `.env`:

```text
ORCA_VERSION=latest          # ou 1.4.192
AUTO_UPDATE_ORCA=false         # true = tenta atualizar a cada start
ORCA_SEED_IN_IMAGE=false     # true = já embute um seed no build (ainda atualizável no volume)
```

Fonte oficial do binário:

```text
https://github.com/stablyai/orca/releases/latest/download/orca-linux.AppImage
```

Estado (pairing, projetos) fica em `~/.config/{orca,Orca}` — **independente do binário**. Trocar o AppImage não desfaz o pair.

## Agentes previstos

| Agente | Default |
|--------|---------|
| Claude Code | on |
| OpenAI Codex CLI | on |
| Gemini CLI | on |
| Cursor CLI | on |
| OpenCode | on |
| Grok | off (até confirmação oficial) |
| Hermes | off |
| Qwen Code | off |
| Kimi | off |

## Requirements

- Docker + Docker Compose v2
- Linux host (recomendado) com `/dev/net/tun` para Tailscale
- Auth key Tailscale (scoped) para o sidecar
- Orca Desktop no cliente para pairing

## Quick start

```bash
cp .env.example .env
# editar: TS_AUTHKEY, ORCA_PAIRING_ADDRESS (IP/hostname Tailscale — não use 0.0.0.0)

docker compose build
docker compose up -d
docker compose logs -f orca
```

Pairing no Orca Desktop:

```text
Settings → Remote Orca Servers → Add Server → colar pairing URL dos logs
```

Os logs devem mostrar algo como:

```text
Orca server ready
Bound endpoint: ws://0.0.0.0:6768
Advertised endpoint: ws://orca-dev:6768
Pairing URL: orca://pair?code=...
```

Autenticar agentes:

```bash
docker compose exec orca bash
claude
codex
gemini
orca account add --agent claude
orca account list
```

Diagnóstico:

```bash
docker compose exec orca /scripts/doctor.sh
docker compose exec orca /scripts/versions.sh
docker compose exec orca /scripts/ports.sh
docker compose exec orca mise run orca:status
docker compose exec orca mise run agents:doctor
```

## Configuration

Ver [`.env.example`](.env.example).

| Variável | Descrição |
|----------|-----------|
| `ORCA_VERSION` | Tag pinada ou `latest` (default) |
| `ORCA_PORT` | Porta do server (default `6768`) |
| `ORCA_PAIRING_ADDRESS` | Host/IP anunciado no pairing (Tailscale) |
| `MUP_SCHEDULE` | Cron in-container (`true`) |
| `MUP_CRON` | Expressão cron (`15 4 * * *`) |
| `MUP_ON_BOOT` | `mup` no start do container (`false`) |
| `TZ` | Fuso do schedule |
| `AUTO_UPDATE_ALL` | Alias de boot mup (`false`) |
| `GIT_USER_NAME` | `git config user.name` no boot |
| `GIT_USER_EMAIL` | `git config user.email` no boot |
| `GIT_INIT_DEFAULT_BRANCH` | default `main` |
| `TS_AUTHKEY` | Auth key do Tailscale |
| `TAILSCALE_HOSTNAME` | MagicDNS name (default `orca-dev`) |
| `INSTALL_*` | Liga/desliga cada agente no build / mup |

## Volumes

| Volume | Path | Conteúdo |
|--------|------|----------|
| `orca-home` | `/home/orca` | **Orca runtime**, credenciais, mise, configs |
| `workspace` | `/workspace` | repositórios e worktrees |
| `tailscale-state` | `/var/lib/tailscale` | identidade do nó Tailscale |

**Não versionar** `data/` nem `.env`. Backup de `orca-home` contém secrets — criptografar.

## Networking

- Nenhuma porta publicada no host por padrão
- Acesso via Tailnet: `http://orca-dev:6768`, `http://orca-dev:3000`, etc.
- Servidores de dev devem escutar em `0.0.0.0` (não só `127.0.0.1`)
- Opcional: Tailscale Serve; **não** usar Funnel por padrão
- Profile `docker-access` para socket (risco elevado)

## Security

- Processo Orca não-root (`user: orca`)
- Sem `--privileged` no Orca
- Sem FUSE
- Sem Docker socket por padrão
- Secrets fora da imagem
- Porta Orca só na Tailnet / rede privada

## Project layout

```text
orca-server/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── config/mise.toml          # tasks: mup, orca:*, agents:*
├── config/mup.crontab        # referência (schedule real via MUP_CRON)
├── docs/IMPLEMENTATION_PLAN.md
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

Ver [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) §90.

| Fase | Foco | Status |
|------|------|--------|
| A | Docker base (Debian Slim, Electron libs, user) | done |
| B | mise (Node, Python, uv) | done |
| C | Orca runtime no volume + update-orca | done |
| D | Tailscale sidecar + portas dinâmicas | **done** (pair OK) |
| E | Agentes + **mup** + schedule **in-container** | **done** (claude/codex/gemini/opencode) |
| F | accounts no host + Cursor oficial | **in progress** (pair done → login agents) |
| G | Agentes opcionais | pending |
| H | Hardening final + teste portas dinâmicas formal | pending |

## Upgrade

```bash
# TUDO (tools + Orca + agents) — sem rebuild, 100% no container
docker compose exec orca mup
# se o binário Orca mudou, o supervisor recicla sozinho

# só Orca
docker compose exec orca update-orca latest

# só agents
docker compose exec orca mise run agents:update

# base image / system libs (raro)
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
