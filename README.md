# orca-server

Workstation remota de desenvolvimento com **Orca Server** headless, **mise**, agentes de IA e acesso privado via **Tailscale sidecar**.

> Status: Fase A–C em andamento. Orca **atualizável sem rebuild** da imagem.

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
- Agendamento no **host** (systemd timer 04:15 + boot) — ver `host/README.md`
- mise para Node/Python/uv e atualização de AI CLIs sem rebuild
- Tailscale sidecar + `network_mode: service:tailscale`
- HOME e workspace persistentes
- Sem Docker socket e sem exposição pública por padrão

## mup — atualizar tudo num comando

```bash
# dentro do container
docker compose exec orca mup
# ou
docker compose exec orca mise run mup

# do host (reinicia Orca se o binário mudou)
./host/host-mup.sh
```

| Componente | Como | Rebuild? |
|------------|------|----------|
| Node / Python / uv | `mise install` + `upgrade` | Não |
| Orca AppImage | volume `~/.local/share/orca` | Não |
| Claude / Codex / Gemini | `npm i -g` → `~/.local` | Não |

Agendamento (madrugada + boot):

```bash
# recomendado
sudo cp host/systemd/orca-mup.{service,timer} /etc/systemd/system/
# ajuste WorkingDirectory se o clone não for /home/avila/Development/orca-server
sudo systemctl daemon-reload
sudo systemctl enable --now orca-mup.timer
```

Detalhes: [host/README.md](host/README.md).

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
| `AUTO_UPDATE_ALL` | No boot: roda `mup` completo (`false` — prefira timer no host) |
| `AUTO_UPDATE_ORCA` | Atualiza Orca no boot (`false` por padrão) |
| `AUTO_UPDATE_AGENTS` | Atualiza agents no boot (`false` por padrão) |
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
├── host/                     # schedule from the Docker host
│   ├── host-mup.sh
│   ├── cron/
│   ├── systemd/
│   └── README.md
├── docs/IMPLEMENTATION_PLAN.md
└── scripts/
    ├── entrypoint.sh
    ├── mup.sh                # update-all orchestrator
    ├── update-orca.sh        # Orca upgrade sem rebuild
    ├── update-agents.sh      # agents upgrade sem rebuild
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
| D | Tailscale sidecar + portas dinâmicas | compose ready |
| E | Agentes principais + **mup** + schedule host | done (scaffold + mup) |
| F | agents:update refinado / canais | partial (via mup) |
| G | Agentes opcionais | pending |
| H | Hardening final | pending |

## Upgrade

```bash
# TUDO (tools + Orca + agents) — sem rebuild
docker compose exec orca mup
# ou do host (com restart automático se Orca mudou)
./host/host-mup.sh

# só Orca
docker compose exec orca update-orca latest
docker compose restart orca

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
