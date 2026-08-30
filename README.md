# orca-server

Workstation remota de desenvolvimento com **Orca Server** headless, **mise**, agentes de IA e acesso privado via **Tailscale sidecar**.

> Status: scaffold inicial baseado no [plano de implementação](docs/IMPLEMENTATION_PLAN.md). Implementação por fases.

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

Características-alvo:

- Debian Slim (sem Ubuntu/Alpine)
- Orca headless (AppImage extraído, sem FUSE / sem `--privileged`)
- mise para Node/Python/uv e atualização de AI CLIs sem rebuild
- Tailscale sidecar + `network_mode: service:tailscale`
- HOME e workspace persistentes
- Sem Docker socket e sem exposição pública por padrão

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

## Quick start (quando a imagem estiver pronta)

```bash
cp .env.example .env
# editar: TS_AUTHKEY, ORCA_PAIRING_ADDRESS (ou deixar descoberta via Tailscale)

docker compose build
docker compose up -d
docker compose logs -f orca
```

Pairing no Orca Desktop:

```text
Settings → Remote Orca Servers → Add Server → colar pairing URL dos logs
```

Autenticar agentes:

```bash
docker compose exec orca bash
claude
codex
gemini
# ...
orca account add --agent claude
orca account list
```

Diagnóstico:

```bash
docker compose exec orca /scripts/doctor.sh
docker compose exec orca /scripts/versions.sh
docker compose exec orca /scripts/ports.sh
mise run agents:doctor
mise run agents:update   # atualiza CLIs sem rebuild
```

## Configuration

Ver [`.env.example`](.env.example).

Principais variáveis:

| Variável | Descrição |
|----------|-----------|
| `ORCA_VERSION` | Versão pinada do Orca AppImage |
| `ORCA_PORT` | Porta do server (default `6768`) |
| `ORCA_PAIRING_ADDRESS` | IP/hostname anunciado no pairing (Tailscale) |
| `TS_AUTHKEY` | Auth key do Tailscale |
| `TAILSCALE_HOSTNAME` | MagicDNS name (default `orca-dev`) |
| `AUTO_UPDATE_AGENTS` | `false` por padrão |
| `INSTALL_*` | Liga/desliga cada agente no build |

## Volumes

| Volume | Path | Conteúdo |
|--------|------|----------|
| `orca-home` | `/home/orca` | credenciais, mise, configs de agentes |
| `workspace` | `/workspace` | repositórios e worktrees |
| `tailscale-state` | `/var/lib/tailscale` | identidade do nó Tailscale |

**Não versionar** `data/` nem `.env`. Backup de `orca-home` contém secrets — criptografar.

## Networking

- Nenhuma porta publicada no host por padrão
- Acesso via Tailnet: `http://orca-dev:6768`, `http://orca-dev:3000`, etc.
- Servidores de dev devem escutar em `0.0.0.0` (não só `127.0.0.1`)
- Opcional: Tailscale Serve; **não** usar Funnel por padrão
- Profile `docker-access` para socket (risco elevado — documentado no plano)

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
├── .dockerignore
├── .env.example
├── README.md
├── config/
│   └── mise.toml
├── docs/
│   └── IMPLEMENTATION_PLAN.md
├── scripts/
│   ├── entrypoint.sh
│   ├── install-orca.sh
│   ├── install-agents.sh
│   ├── doctor.sh
│   ├── versions.sh
│   └── ports.sh
└── data/                 # local only, gitignored
    ├── home/
    └── workspace/
```

## Implementation phases

Ver ordem completa em [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) §90:

| Fase | Foco |
|------|------|
| A | Docker base (Debian Slim, user, volumes) |
| B | mise (Node, Python, uv, tasks) |
| C | Orca (extract AppImage, wrapper, serve) |
| D | Tailscale sidecar + portas dinâmicas |
| E | Agentes principais |
| F | agents:update / versions / doctor |
| G | Agentes opcionais (após confirmação oficial) |
| H | Segurança, healthchecks, README final |

## Upgrade

```bash
# runtime base / Orca
docker compose build --pull
docker compose up -d

# AI CLIs (sem rebuild)
docker compose exec orca mise run agents:update
```

## Troubleshooting

```bash
docker compose logs -f tailscale
docker compose logs -f orca
docker compose exec orca /scripts/doctor.sh
docker compose exec orca /scripts/ports.sh
```

## License

Private — all rights reserved until otherwise stated.
