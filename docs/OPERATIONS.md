# Operação — orca-server

Tudo roda **no container**. O host só faz `docker compose up/down`.

## Status atual (A–E + pair)

| Item | Estado |
|------|--------|
| Tailscale nó | `orca-dev` (MagicDNS) |
| Orca | volume `~/.local/share/orca`, update sem rebuild |
| mup | supercronic 04:15 `America/Sao_Paulo` |
| Agents no volume | claude, codex, gemini, opencode |
| Pairing | via `orca://pair?code=…` no Desktop |

## Pair (já validado)

1. Client na mesma Tailnet.
2. Logs:
   ```bash
   docker compose logs orca 2>&1 | grep 'Pairing URL'
   ```
3. Desktop: Settings → Remote Orca Servers → colar URL.
4. Endpoint anunciado: `ws://orca-dev:6768` (bind real `0.0.0.0:6768`).

O link é um **offer v2** (endpoint + deviceToken + publicKey) em Base64URL — ver análise no histórico da sessão.

## Contas de agents (próximo passo operacional)

O CLI `orca account *` **não** sobe como segundo processo enquanto `orca serve` está no ar
(single-instance lock do Electron no mesmo `userData`). Preferir:

### A) Pelo Orca Desktop (recomendado após pair)

No runtime remoto pairado: adicionar contas Claude/Codex pela UI do Orca
(managed accounts no host).

### B) Login nativo no container (credenciais no volume HOME)

```bash
docker compose exec orca bash
# PATH já inclui ~/.local/bin + mise shims

claude          # ou: claude auth login
codex login     # fluxo oficial OpenAI
gemini          # auth Google conforme CLI
opencode        # auth conforme CLI
```

Credenciais ficam em `~/.claude`, `~/.codex`, etc. no volume **orca-home** — sobrevivem restart e `mup`.

### C) Via Orca CLI (só se serve estiver parado)

```bash
docker compose stop orca
docker compose run --rm --entrypoint /scripts/entrypoint.sh orca orca account add --agent claude
# … depois compose start de novo
```

Na prática, **A ou B** são melhores.

## Update sem rebuild

```bash
docker compose exec orca mup                 # tools + agents (+ orca se MUP_ORCA)
docker compose exec orca mise run agents:update
docker compose exec orca update-orca latest  # supervisor recicla se binário mudou
docker compose exec orca /scripts/doctor.sh
```

## Portas dinâmicas (Tailnet)

Sem publicar no host. Qualquer processo no container escutando `0.0.0.0:<porta>`
fica acessível como `http://orca-dev:<porta>` na Tailnet.

Teste manual:

```bash
docker compose exec orca python3 -m http.server 9123 --bind 0.0.0.0
# noutro device da tailnet: http://orca-dev:9123
```

## Arquivos sensíveis

- `.env` (TS_AUTHKEY) — gitignored, nunca commit
- volume `orca-home` — pairing state + agent creds (backup criptografado)

## Comandos úteis

```bash
docker compose ps
docker compose logs -f orca
docker compose exec orca /scripts/update-orca.sh --status
docker compose exec orca mise run agents:versions
tailscale status | grep orca-dev   # no host
```
