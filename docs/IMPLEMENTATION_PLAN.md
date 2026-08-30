# Plano de Implementação — Orca Server em Docker (Debian Slim)

## 1. Objetivo

Criar uma imagem Docker enxuta, baseada em **Debian Slim**, capaz de executar o **Orca Server em modo headless** e disponibilizar múltiplos agentes/CLIs de IA no mesmo ambiente.

O container deve ser adequado para execução contínua em servidor/VPS e posteriormente poder ser publicado via Docker Compose, Dokploy ou plataforma equivalente.

O ambiente deve suportar inicialmente:

- Orca Server
- Claude Code
- OpenAI Codex CLI
- Cursor CLI
- Gemini CLI
- Grok
- OpenCode
- Hermes
- Qwen Code
- Kimi
- GitHub CLI
- ferramentas comuns de desenvolvimento

A implementação deve ser modular: novos agentes CLI devem poder ser adicionados posteriormente sem reestruturar a imagem inteira.

---

## 2. Princípios da solução

### Base

Usar:

```dockerfile
FROM debian:trixie-slim
```

Se houver incompatibilidade comprovada com algum binário, permitir fallback para:

```dockerfile
FROM debian:bookworm-slim
```

Não usar Ubuntu.

Não usar Alpine porque vários binários distribuídos para Linux dependem de glibc e o Alpine utiliza musl.

---

## 3. Arquitetura

```text
Notebook/Desktop
└── Orca IDE
      │
      │ rede privada
      │ Tailscale / WireGuard / LAN
      ▼
Docker Host
└── Container: orca-server
      │
      ├── Orca Server
      │     └── orca serve :6768
      │
      ├── Git / GitHub CLI
      │
      ├── Agents
      │     ├── Claude Code
      │     ├── Codex
      │     ├── Cursor CLI
      │     ├── Gemini CLI
      │     ├── Grok
      │     ├── OpenCode
      │     ├── Hermes
      │     ├── Qwen Code
      │     └── Kimi
      │
      ├── /home/orca
      │     └── configurações e credenciais persistentes
      │
      └── /workspace
            └── repositórios e worktrees
```

O Orca remoto deve ser o proprietário do runtime.

Projetos, worktrees, terminais, sessões e agentes devem continuar existindo mesmo quando o notebook cliente estiver desconectado.

---

## 4. Estrutura do projeto

Criar:

```text
orca-server/
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .env.example
├── README.md
├── scripts/
│   ├── entrypoint.sh
│   ├── install-orca.sh
│   ├── install-agents.sh
│   ├── doctor.sh
│   └── versions.sh
└── data/
    ├── home/
    └── workspace/
```

Não versionar `data/`.

---

## 5. Orca Server

O Orca disponibiliza oficialmente modo headless:

```bash
orca serve
```

No Linux headless/Docker, utilizar o AppImage oficial.

### Requisito importante

Containers Docker normalmente não possuem FUSE.

Portanto NÃO executar o AppImage através de FUSE.

Durante o build:

```bash
./orca-linux.AppImage --appimage-extract
```

Depois executar diretamente:

```bash
/opt/orca/squashfs-root/AppRun serve
```

Isso evita:

- `--privileged`
- `/dev/fuse`
- dependência do FUSE em runtime

Instalar requisitos Linux necessários, incluindo:

```text
curl
ca-certificates
file
jq
xvfb
zlib1g-dev
```

Adicionar bibliotecas que o AppImage Electron exigir apenas após validação real com `ldd`.

Não instalar pacotes desnecessários preventivamente.

---

## 6. Versionamento do Orca

NÃO depender permanentemente de:

```text
releases/latest
```

O Docker build deve aceitar:

```text
ORCA_VERSION
```

Exemplo:

```dockerfile
ARG ORCA_VERSION=1.4.185
```

O download deve apontar para uma versão específica.

Registrar a versão instalada em:

```text
/opt/orca/VERSION
```

O build deve falhar caso o download ou extração falhe.

Idealmente suportar SHA256 através de:

```text
ORCA_SHA256
```

Se fornecido, validar antes de instalar.

---

## 7. Usuário do container

Não executar os agentes como root.

Criar:

```text
user: orca
home: /home/orca
```

UID/GID devem poder ser configurados no build:

```text
PUID
PGID
```

O processo principal do Orca deve rodar como esse usuário.

Garantir ownership correto de:

```text
/home/orca
/workspace
/opt/orca
```

---

## 8. Persistência

Persistir:

```yaml
volumes:
  - ./data/home:/home/orca
  - ./data/workspace:/workspace
```

Dentro do HOME serão persistidos, entre outros:

```text
~/.claude
~/.codex
~/.cursor
~/.gemini
~/.config
~/.local
~/.cache
~/.ssh
~/.gitconfig
```

Não criar volume separado para cada ferramenta sem necessidade.

Persistir o HOME inteiro simplifica autenticação e atualização futura.

---

## 9. Node.js

Muitos agentes utilizam Node.

Instalar uma versão LTS moderna.

Preferência:

```text
Node.js 22 LTS
```

Não depender do Node antigo disponível no repositório padrão do Debian caso ele esteja defasado.

O método de instalação precisa:

- funcionar em Debian
- ser reproduzível
- não instalar toolchains desnecessárias
- permitir atualização simples

Disponibilizar:

```text
node
npm
npx
```

Opcionalmente:

```text
pnpm
```

Não instalar Yarn/Bun inicialmente sem necessidade comprovada.

---

## 10. Python

Instalar:

```text
python3
python3-venv
```

Instalar `uv`.

Evitar `pip install` global no Python do sistema.

Projetos Python devem utilizar virtualenv/uv.

---

## 11. Ferramentas essenciais

Instalar no container:

```text
bash
git
openssh-client
curl
wget
ca-certificates
jq
less
nano
vim-tiny
procps
psmisc
unzip
zip
tar
gzip
file
ripgrep
fd-find
fzf
build-essential
python3
python3-venv
```

Instalar GitHub CLI (`gh`) usando fonte oficial.

Criar alias:

```bash
fd -> fdfind
```

se necessário no Debian.

---

## 12. Claude Code

Instalar seguindo o método oficial disponível no momento da implementação.

Atualmente pode ser instalado via:

```bash
npm install -g @anthropic-ai/claude-code
```

Validar:

```bash
claude --version
```

Autenticação deve ocorrer após o container estar rodando:

```bash
docker exec -it orca-server bash
claude
```

O Orca detecta automaticamente:

```text
~/.claude
```

No host headless também deverá ser possível registrar a conta através do Orca:

```bash
orca account add --agent claude
```

No nosso container, se o binário usado for `AppRun`, criar wrapper `/usr/local/bin/orca` para permitir isso.

---

## 13. OpenAI Codex CLI

Instalar:

```bash
npm install -g @openai/codex
```

Validar:

```bash
codex --version
```

Persistir:

```text
~/.codex
```

Autenticar dentro do container.

Registrar no Orca:

```bash
orca account add --agent codex
```

O Orca possui integração nativa com `~/.codex`.

---

## 14. Gemini CLI

Instalar:

```bash
npm install -g @google/gemini-cli
```

Requer Node moderno.

Validar:

```bash
gemini --version
```

Autenticação deve ser feita dentro do container e persistida em `/home/orca`.

---

## 15. Cursor CLI

Não assumir nome de pacote npm.

Consultar a documentação oficial atual do Cursor CLI durante a implementação.

Instalar pelo método oficial.

Depois validar se o executável está disponível no PATH.

O Orca detecta o Cursor CLI através do PATH.

Adicionar o instalador em função independente em:

```text
scripts/install-agents.sh
```

O build não deve quebrar todo o servidor caso Cursor altere seu instalador.

Preferencialmente permitir:

```text
INSTALL_CURSOR=true|false
```

---

## 16. Grok

O Orca possui suporte para Grok entre seus agentes.

Antes de instalar qualquer pacote:

1. verificar qual CLI o Orca espera atualmente;
2. identificar o comando executável esperado;
3. utilizar somente fonte oficial;
4. não instalar pacote npm apenas porque possui nome semelhante.

Adicionar flag:

```text
INSTALL_GROK=true|false
```

Se não houver CLI oficial/distribuição confiável no momento do build, documentar e deixar desabilitado sem comprometer os demais agentes.

---

## 17. OpenCode

Instalar usando método oficial atual.

Validar executável:

```bash
opencode --version
```

Adicionar flag:

```text
INSTALL_OPENCODE=true
```

---

## 18. Hermes

Instalar somente após verificar qual projeto Hermes é suportado pelo Orca no momento.

Não inferir pacote pelo nome.

Validar:

```bash
hermes --version
```

ou o comando oficialmente utilizado pela integração.

Adicionar:

```text
INSTALL_HERMES=true|false
```

---

## 19. Qwen Code

Instalar somente pela distribuição oficial.

Validar o nome real do binário.

Adicionar:

```text
INSTALL_QWEN=true|false
```

---

## 20. Kimi

Instalar somente pela distribuição oficial suportada pelo Orca.

Adicionar:

```text
INSTALL_KIMI=true|false
```

---

## 21. Instalação modular de agentes

`scripts/install-agents.sh` deve possuir funções separadas:

```bash
install_claude
install_codex
install_gemini
install_cursor
install_grok
install_opencode
install_hermes
install_qwen
install_kimi
```

Cada função deve:

1. instalar;
2. verificar existência do executável;
3. imprimir versão;
4. retornar erro compreensível.

Utilizar argumentos/ENV para habilitar ou desabilitar agentes.

Exemplo:

```text
INSTALL_CLAUDE=true
INSTALL_CODEX=true
INSTALL_GEMINI=true
INSTALL_CURSOR=true
INSTALL_GROK=true
INSTALL_OPENCODE=true
INSTALL_HERMES=true
INSTALL_QWEN=true
INSTALL_KIMI=true
```

---

## 22. Wrapper `orca`

Como o AppImage será extraído, criar:

```text
/usr/local/bin/orca
```

Exemplo conceitual:

```bash
#!/bin/sh
exec /opt/orca/squashfs-root/AppRun "$@"
```

Assim estes comandos devem funcionar:

```bash
orca serve
orca account list
orca account add --agent claude
orca account add --agent codex
orca skills list
```

---

## 23. Entrypoint

Criar:

```text
/scripts/entrypoint.sh
```

Ele deve:

1. verificar permissões dos diretórios persistentes;
2. garantir `/workspace`;
3. garantir HOME correto;
4. opcionalmente executar diagnóstico;
5. iniciar Xvfb se o Orca exigir display mesmo em modo headless;
6. iniciar Orca Server.

Comando final:

```bash
exec orca serve \
  --port "${ORCA_PORT:-6768}" \
  --pairing-address "${ORCA_PAIRING_ADDRESS}"
```

Se `ORCA_PAIRING_ADDRESS` não estiver definido:

- não inventar IP;
- detectar somente se existir método confiável;
- caso contrário imprimir instrução clara e encerrar.

Para ambiente local pode ser permitido configurar explicitamente:

```text
ORCA_PAIRING_ADDRESS=192.168.1.10
```

ou um IP Tailscale:

```text
ORCA_PAIRING_ADDRESS=100.x.y.z
```

---

## 24. Xvfb

Como o runtime é derivado da aplicação Electron, preparar suporte a Xvfb.

Exemplo:

```bash
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
```

Não usar desktop environment.

Não instalar:

```text
GNOME
KDE
XFCE
VNC
```

O objetivo é manter o container headless e enxuto.

---

## 25. Docker Compose

Criar `docker-compose.yml`.

Base:

```yaml
services:
  orca:
    build:
      context: .
    container_name: orca-server
    restart: unless-stopped

    environment:
      HOME: /home/orca
      ORCA_PORT: 6768
      ORCA_PAIRING_ADDRESS: ${ORCA_PAIRING_ADDRESS}

    volumes:
      - ./data/home:/home/orca
      - ./data/workspace:/workspace

    ports:
      - "6768:6768"
```

### Segurança

A porta `6768` NÃO deve ser publicada diretamente na Internet.

Preferências:

1. Tailscale
2. WireGuard
3. rede privada
4. SSH tunnel

Caso Docker Host esteja acessível publicamente, firewall deve bloquear 6768 para Internet.

---

## 26. Tailscale

Não colocar Tailscale dentro do mesmo container inicialmente.

Preferência arquitetural:

```text
Host
├── Tailscale
└── Docker
     └── Orca
```

Vantagens:

- container mais simples;
- menos capabilities;
- sem `/dev/net/tun`;
- host controla firewall/rede;
- atualização independente.

O `ORCA_PAIRING_ADDRESS` deve receber o IP Tailscale do host.

Caso o networking Docker impeça o acesso esperado, avaliar:

```yaml
network_mode: host
```

somente em Linux.

Preferir bridge inicialmente.

---

## 27. Docker socket

NÃO montar por padrão:

```text
/var/run/docker.sock
```

Isso equivale praticamente a dar acesso root ao host.

Criar perfil opcional no Compose:

```text
ENABLE_DOCKER_SOCKET=false
```

Se futuramente os agentes precisarem operar containers:

- documentar explicitamente o risco;
- considerar Docker Socket Proxy;
- considerar Docker-in-Docker isolado;
- somente montar socket direto se for decisão consciente.

---

## 28. SSH

Persistir:

```text
/home/orca/.ssh
```

Mas não copiar chaves privadas para dentro da imagem.

As chaves devem entrar somente via volume/secret em runtime.

Garantir:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/*
```

quando aplicável.

---

## 29. Secrets

Não colocar no Dockerfile:

```text
OPENAI_API_KEY
ANTHROPIC_API_KEY
GEMINI_API_KEY
XAI_API_KEY
GITHUB_TOKEN
```

Usar:

- `.env`
- Docker secrets
- secrets do Dokploy
- autenticação interativa persistida no HOME

Adicionar `.env` ao `.gitignore`.

`.env.example` deve conter somente nomes, sem valores reais.

---

## 30. Healthcheck

Não simplesmente verificar se o processo existe.

Criar healthcheck que teste se a porta/runtime está ativo.

Se Orca expuser endpoint HTTP confiável, usar esse endpoint.

Caso não exista endpoint documentado:

```bash
nc -z 127.0.0.1 6768
```

ou equivalente.

Não inventar `/health`.

---

## 31. Doctor

Criar:

```text
scripts/doctor.sh
```

Saída desejada:

```text
[OK] Orca
[OK] git
[OK] gh
[OK] node
[OK] npm
[OK] python
[OK] uv
[OK] claude
[OK] codex
[OK] gemini
[OK] cursor
[OK] opencode
...
```

Para ferramentas opcionais ausentes:

```text
[SKIP] Grok not installed
```

Não marcar como erro se explicitamente desabilitada.

---

## 32. Versions

Criar:

```text
scripts/versions.sh
```

Deve mostrar todas as versões instaladas.

Exemplo:

```text
Orca: 1.4.xxx
Node: ...
npm: ...
Python: ...
uv: ...
git: ...
gh: ...
Claude: ...
Codex: ...
Gemini: ...
Cursor: ...
OpenCode: ...
```

Isso será útil para troubleshooting e upgrades.

---

## 33. Atualização

Agentes não devem se atualizar automaticamente durante startup.

Atualizações devem ocorrer via rebuild da imagem.

Fluxo:

```bash
docker compose build --pull
docker compose up -d
```

Credenciais e projetos permanecem nos volumes.

Versões principais devem poder ser fixadas por `ARG`.

Exemplo:

```text
ORCA_VERSION
NODE_VERSION
```

Para agentes npm pode inicialmente utilizar versões fixadas através de ARGs:

```text
CLAUDE_VERSION
CODEX_VERSION
GEMINI_VERSION
```

Permitir `latest` somente quando explicitamente configurado.

---

## 34. Multi-stage build

Avaliar multi-stage build para reduzir tamanho final.

Objetivo:

- baixar/extrair artefatos no builder;
- copiar somente runtime necessário;
- remover cache apt/npm;
- não manter compiladores caso nenhum agente precise deles em runtime.

Porém não sacrificar compatibilidade dos agentes por alguns MB.

Prioridade:

1. funcionamento;
2. reproducibilidade;
3. segurança;
4. tamanho.

---

## 35. Build cache

Usar boas práticas:

```bash
apt-get update \
 && apt-get install -y --no-install-recommends ... \
 && rm -rf /var/lib/apt/lists/*
```

Limpar:

```text
npm cache
/tmp
download artifacts
```

Não remover caches dentro do HOME persistente em runtime.

---

## 36. Logs

Orca Server deve escrever stdout/stderr diretamente para Docker.

Não criar arquivo de log interno como mecanismo principal.

Permitir:

```bash
docker logs -f orca-server
```

O pairing URL emitido pelo `orca serve` deve aparecer nos logs.

---

## 37. Primeiro boot

Fluxo esperado:

```bash
cp .env.example .env
```

Configurar:

```text
ORCA_PAIRING_ADDRESS=<IP_PRIVADO_DO_HOST>
```

Depois:

```bash
docker compose build
docker compose up -d
docker logs -f orca-server
```

Copiar a URL de pairing mostrada pelo Orca.

No desktop:

```text
Settings
→ Remote Orca Servers
→ Add Server
→ colar pairing URL
```

---

## 38. Autenticação dos agentes

Após primeiro boot:

```bash
docker exec -it orca-server bash
```

Executar autenticação necessária:

```bash
claude
codex
gemini
cursor
opencode
```

Para Claude/Codex, preferir também testar:

```bash
orca account add --agent claude
orca account add --agent codex
orca account list
```

Todas as credenciais devem sobreviver:

```bash
docker compose down
docker compose up -d
```

---

## 39. Git

Dentro do container permitir configuração:

```bash
git config --global user.name
git config --global user.email
```

O arquivo ficará persistido em:

```text
/home/orca/.gitconfig
```

Testar:

```bash
git clone
git fetch
git worktree add
git commit
git push
```

---

## 40. GitHub CLI

Permitir:

```bash
gh auth login
```

Credenciais devem permanecer no HOME persistente.

Testar:

```bash
gh auth status
```

---

## 41. Workspaces

Diretório padrão:

```text
/workspace
```

Projetos adicionados ao Orca devem ficar nesse filesystem persistente.

Nunca utilizar diretório temporário do container para projetos.

Testar criação/remoção de worktrees e persistência após restart.

---

## 42. Requisitos de segurança

Obrigatórios:

- processo não-root;
- sem `--privileged`;
- sem FUSE;
- sem Docker socket por padrão;
- porta Orca fora da Internet pública;
- secrets fora da imagem;
- HOME persistente;
- versões auditáveis;
- downloads oficiais;
- evitar `curl | sh` quando houver alternativa segura;
- quando `curl | sh` for único método oficial, revisar script/origem e fixar versão quando possível.

---

## 43. README

README deve conter somente instruções úteis e reproduzíveis.

Seções:

```text
Requirements
Build
Configuration
Start
Pair Orca Desktop
Authenticate agents
Volumes
Networking
Security
Upgrade
Backup
Troubleshooting
```

Adicionar comando rápido:

```bash
./scripts/doctor.sh
```

ou:

```bash
docker exec -it orca-server /scripts/doctor.sh
```

---

## 44. Backup

Backup mínimo:

```text
data/home
data/workspace
```

Não incluir esses diretórios na imagem.

Documentar que `data/home` contém credenciais sensíveis.

Backup deve ser criptografado.

---

## 45. Critérios de aceite — Infraestrutura

A implementação só está pronta quando:

- [ ] `docker compose build` termina sem erros;
- [ ] imagem usa Debian Slim;
- [ ] container não roda como root;
- [ ] container não requer `--privileged`;
- [ ] container não depende de FUSE;
- [ ] Orca inicia em headless;
- [ ] porta 6768 fica ativa;
- [ ] pairing URL é gerada;
- [ ] Orca Desktop conecta no servidor;
- [ ] restart do container preserva configuração;
- [ ] restart do container preserva projetos;
- [ ] restart do container preserva credenciais.

---

## 46. Critérios de aceite — Orca

Validar:

```bash
orca serve
orca account list
orca skills list
```

Dentro do Orca remoto:

- [ ] abrir projeto;
- [ ] criar worktree;
- [ ] abrir terminal;
- [ ] iniciar agente;
- [ ] fechar cliente desktop;
- [ ] reconectar;
- [ ] sessão continuar disponível.

---

## 47. Critérios de aceite — agentes

### Claude

```bash
claude --version
```

- [ ] autentica;
- [ ] Orca detecta;
- [ ] executa dentro de worktree.

### Codex

```bash
codex --version
```

- [ ] autentica;
- [ ] Orca lê `~/.codex`;
- [ ] executa dentro de worktree.

### Gemini

```bash
gemini --version
```

- [ ] autentica;
- [ ] executa dentro de worktree.

### Cursor

- [ ] CLI oficial instalada;
- [ ] binário presente no PATH;
- [ ] Orca detecta;
- [ ] executa dentro de worktree.

### OpenCode

- [ ] instalado;
- [ ] autenticado;
- [ ] executa pelo Orca.

### Grok / Hermes / Qwen / Kimi

Para cada agente:

- [ ] integração atual do Orca confirmada;
- [ ] distribuição oficial identificada;
- [ ] executável esperado identificado;
- [ ] instalação reproduzível;
- [ ] aparece no PATH;
- [ ] inicia pelo Orca.

Não criar instalação fictícia só para marcar o checkbox.

---

## 48. Teste de persistência

Executar:

```bash
docker compose up -d
```

Autenticar os agentes.

Criar repo/worktree.

Depois:

```bash
docker compose down
docker compose up -d
```

Confirmar:

- agentes continuam autenticados;
- repositórios permanecem;
- worktrees permanecem;
- Orca reconhece estado anterior.

---

## 49. Teste de atualização

1. Subir versão A.
2. Criar sessões/configuração.
3. Alterar `ORCA_VERSION`.
4. Rebuild.
5. Subir versão B.
6. Confirmar volumes intactos.
7. Confirmar pairing/runtime funcionando.
8. Confirmar agentes funcionando.

---

## 50. Não fazer

Não:

- usar Ubuntu;
- usar Alpine;
- instalar GUI completa;
- instalar VNC;
- usar systemd dentro do container;
- usar supervisord sem necessidade;
- executar container privilegiado;
- usar FUSE;
- embutir tokens;
- copiar `~/.ssh` no Dockerfile;
- expor Orca diretamente na Internet;
- montar Docker socket por padrão;
- inventar endpoints de health;
- instalar pacotes não oficiais chamados "grok", "kimi", "hermes" etc. sem confirmação.

---

## 51. Ordem de implementação para o Codex

Executar nesta ordem.

### Fase 1 — Base

1. Criar estrutura.
2. Criar Debian Slim.
3. Criar usuário `orca`.
4. Instalar dependências básicas.
5. Instalar Node/Python/uv/git/gh.

### Fase 2 — Orca

6. Baixar versão fixa do Orca.
7. Extrair AppImage.
8. Criar wrapper `orca`.
9. Configurar Xvfb.
10. Fazer `orca serve` iniciar.

PARAR aqui e validar Orca Server antes dos agentes.

### Fase 3 — agentes principais

11. Claude Code.
12. Codex.
13. Gemini.
14. Cursor.
15. OpenCode.

Testar cada um individualmente.

### Fase 4 — agentes adicionais

16. Grok.
17. Hermes.
18. Qwen.
19. Kimi.

Antes de cada instalação pesquisar a documentação oficial atual e integração atual do Orca.

### Fase 5 — persistência

20. HOME.
21. workspace.
22. autenticação.
23. restart.

### Fase 6 — segurança

24. usuário não-root.
25. secrets.
26. networking.
27. healthcheck.
28. revisar permissões.

### Fase 7 — qualidade

29. doctor.
30. versions.
31. README.
32. teste completo.
33. reduzir imagem sem quebrar funcionalidade.

---

## 52. Instrução principal para o Codex

Você está implementando esta especificação.

Regras:

1. Não assuma APIs, URLs de download, nomes de pacotes ou comandos que não tenham sido confirmados.
2. Pesquise documentação oficial atual antes de instalar integrações que possam ter mudado.
3. Priorize fontes oficiais dos fabricantes e o repositório/documentação oficial do Orca.
4. Não substitua uma integração inexistente por pacote de terceiros com nome parecido.
5. Faça alterações incrementais.
6. Rode build/testes após cada fase.
7. Quando algo não estiver disponível oficialmente, deixe a integração opcional e documente.
8. Não comprometa os agentes já funcionais por causa de um agente opcional.
9. Mantenha o container enxuto.
10. Não usar Ubuntu nem Alpine.
11. Não usar FUSE nem `--privileged`.
12. Não montar Docker socket por padrão.
13. Não expor credenciais.
14. Ao final, executar e registrar os testes dos critérios de aceite.

---

## 53. Referências oficiais a consultar durante a implementação

Orca:

```text
https://www.onorca.dev/docs/remote-servers
https://www.onorca.dev/docs/agents/supported
https://www.onorca.dev/docs/cli/reference
https://www.onorca.dev/docs/install
https://github.com/stablyai/orca
https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md
```

OpenAI Codex:

```text
https://github.com/openai/codex
https://help.openai.com/
```

Claude Code:

```text
https://docs.anthropic.com/
```

Gemini CLI:

```text
https://github.com/google-gemini/gemini-cli
```

Para Cursor, Grok, OpenCode, Hermes, Qwen e Kimi: localizar a documentação oficial vigente no momento da implementação e registrar no README qual fonte foi utilizada.

---

## 54. Resultado esperado

Ao final deverá ser possível fazer:

```bash
git clone <repo-do-orca-server-docker>
cd orca-server
cp .env.example .env

# configurar ORCA_PAIRING_ADDRESS

docker compose build
docker compose up -d
docker logs -f orca-server
```

Depois conectar o Orca Desktop ao pairing URL e utilizar múltiplos agentes no servidor remoto.

O notebook deve atuar somente como cliente.

Todo processamento, terminal, Git/worktrees e agentes devem rodar no servidor Docker.


---

# REVISÃO ARQUITETURAL — mise + Tailscale Sidecar

> Esta seção substitui decisões anteriores conflitantes. Em caso de divergência, **esta revisão prevalece**.

## 55. Arquitetura final

A stack deve ser composta por dois containers principais:

```text
Docker Compose
│
├── tailscale
│   ├── nó próprio na Tailnet
│   ├── estado persistente
│   ├── MagicDNS
│   └── namespace de rede compartilhado
│
└── orca-dev
    ├── Debian Slim
    ├── Orca Server
    ├── mise
    │   ├── Node
    │   ├── Python
    │   ├── uv
    │   └── ferramentas gerenciáveis
    ├── Claude Code
    ├── Codex
    ├── Gemini CLI
    ├── Cursor CLI
    ├── OpenCode
    ├── Grok
    ├── Hermes
    ├── Qwen
    ├── Kimi
    └── /workspace
        ├── projeto A :3000
        ├── projeto B :8000
        ├── projeto C :8080
        └── portas dinâmicas
```

O container `orca-dev` deve utilizar:

```yaml
network_mode: "service:tailscale"
```

Dessa forma, Tailscale e Orca compartilham o mesmo namespace de rede.

O nó Tailscale representa todo o ambiente remoto.

---

## 56. Objetivo de rede

Não publicar individualmente as portas de desenvolvimento através de:

```yaml
ports:
  - "3000:3000"
  - "8000:8000"
  - "8080:8080"
```

A intenção é que qualquer servidor iniciado dentro do ambiente possa ser acessado diretamente pela Tailnet.

Exemplo:

```text
orca-dev:6768   -> Orca
orca-dev:3000   -> frontend
orca-dev:8000   -> API
orca-dev:8080   -> aplicação Java
orca-dev:5173   -> Vite
orca-dev:4200   -> Angular
orca-dev:5000   -> serviço auxiliar
```

Não limitar previamente quais portas podem ser utilizadas.

---

## 57. Regra para servidores de desenvolvimento

Para acesso pela Tailnet, servidores criados pelos agentes devem escutar em:

```text
0.0.0.0
```

e não exclusivamente:

```text
127.0.0.1
```

Exemplos:

### Vite

```bash
npm run dev -- --host 0.0.0.0
```

### Uvicorn

```bash
uvicorn app:app --host 0.0.0.0 --port 8000
```

### Angular

```bash
ng serve --host 0.0.0.0
```

### Next.js

```bash
next dev -H 0.0.0.0
```

Essa regra deve constar no README e nas instruções para agentes.

---

## 58. Tailscale como sidecar

Usar imagem oficial:

```yaml
tailscale:
  image: tailscale/tailscale:latest
```

Preferencialmente permitir fixar a versão através de `.env`.

Exemplo conceitual:

```yaml
services:

  tailscale:
    image: tailscale/tailscale:${TAILSCALE_VERSION:-latest}
    hostname: ${TAILSCALE_HOSTNAME:-orca-dev}

    environment:
      TS_AUTHKEY: ${TS_AUTHKEY}
      TS_STATE_DIR: /var/lib/tailscale
      TS_USERSPACE: "false"

    volumes:
      - tailscale-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun

    cap_add:
      - NET_ADMIN
      - NET_RAW

    restart: unless-stopped

  orca:
    build:
      context: .

    network_mode: "service:tailscale"

    depends_on:
      - tailscale

    environment:
      HOME: /home/orca
      ORCA_PORT: 6768

    volumes:
      - orca-home:/home/orca
      - workspace:/workspace

    restart: unless-stopped
```

Validar a sintaxe final contra a documentação oficial atual do Tailscale antes de concluir.

---

## 59. Persistência do Tailscale

Persistir:

```text
/var/lib/tailscale
```

em volume dedicado:

```yaml
volumes:
  tailscale-state:
```

Objetivo:

- preservar identidade do nó;
- evitar novo registro a cada restart;
- manter configuração;
- reduzir necessidade de reutilizar auth key.

Nunca armazenar `TS_AUTHKEY` dentro da imagem.

---

## 60. Auth Key do Tailscale

`TS_AUTHKEY` deve entrar por:

- secret do Dokploy;
- variável protegida;
- Docker secret;
- `.env` somente em ambiente local.

`.env.example`:

```text
TAILSCALE_HOSTNAME=orca-dev
TAILSCALE_VERSION=latest
TS_AUTHKEY=
```

Não versionar `.env`.

Quando possível, usar auth key:

- scoped;
- reusable somente se necessário;
- ephemeral somente se compatível com a persistência desejada;
- com tags apropriadas.

Documentar ACL/grants recomendados.

---

## 61. MagicDNS

O hostname esperado deve ser:

```text
orca-dev
```

Com MagicDNS habilitado, o cliente deve conseguir acessar:

```text
http://orca-dev:3000
http://orca-dev:8000
http://orca-dev:8080
```

e Orca através da porta correspondente.

Não depender de IP Tailscale fixado manualmente quando MagicDNS estiver disponível.

---

## 62. Tailscale Serve

Suportar opcionalmente Tailscale Serve.

Objetivo:

transformar um serviço interno:

```text
http://127.0.0.1:3000
```

em endpoint HTTPS privado da Tailnet.

Exemplo conceitual:

```text
https://orca-dev.<tailnet>.ts.net
```

Não configurar Serve automaticamente para todas as portas.

Criar documentação/comandos auxiliares para o usuário habilitar quando desejar.

Não utilizar Funnel por padrão.

---

## 63. Segurança de rede

Por padrão:

- nenhuma porta de desenvolvimento deve ser publicada na interface pública do host;
- acesso deve ocorrer via Tailnet;
- aplicar ACL/grants do Tailscale;
- Orca Server não deve ficar diretamente disponível na Internet;
- bancos de dados também devem permanecer privados.

Exemplo de recursos privados:

```text
:5432 PostgreSQL
:6379 Redis
:27017 MongoDB
:9200 Elasticsearch
```

O fato de uma porta estar acessível na Tailnet não significa que ela deva ser aberta para todos os membros.

Documentar controle por ACL/grants.

---

# mise

## 64. mise como gerenciador central

Adicionar **mise** como componente obrigatório.

O mise deve gerenciar:

- runtimes;
- versões;
- ferramentas compatíveis;
- tasks de manutenção;
- atualização dos AI CLIs quando adequado.

Arquitetura:

```text
Debian Slim
│
├── Orca runtime
│
└── mise
    ├── Node
    ├── Python
    ├── uv
    ├── ferramentas
    └── tasks
        ├── agents:update
        ├── agents:versions
        └── agents:doctor
```

Não instalar Node/Python manualmente fora do mise sem necessidade técnica comprovada.

---

## 65. Instalação do mise

Instalar mise usando método oficial para Debian/Linux.

Fixar versão quando possível.

Validar:

```bash
mise --version
```

Adicionar corretamente ao PATH do usuário `orca`.

Não depender de `.bashrc` para funcionamento do processo Docker.

O PATH deve funcionar em shell interativo e não interativo.

---

## 66. Persistência do mise

Persistir dados do mise dentro do HOME:

```text
/home/orca/.local/share/mise
/home/orca/.config/mise
/home/orca/.cache/mise
```

Como `/home/orca` já é persistente, instalações e configurações sobrevivem ao restart/rebuild.

Isso permite atualizar agentes sem reconstruir toda a imagem.

---

## 67. Configuração mise

Criar configuração versionada do projeto, preferencialmente:

```text
/config/mise.toml
```

ou equivalente.

No primeiro boot, disponibilizar configuração base para o usuário.

Não sobrescrever automaticamente configurações personalizadas existentes no volume.

Exemplo conceitual:

```toml
[tools]
node = "22"
python = "3.13"
uv = "latest"
```

As versões reais devem ser verificadas no momento da implementação.

---

## 68. AI CLIs e mise

Existem três categorias.

### Categoria A — gerenciável diretamente pelo mise

Quando existir backend/plugin confiável do mise, utilizar:

```text
mise use ...
```

### Categoria B — pacote npm

Para agentes oficialmente distribuídos via npm, usar o Node fornecido pelo mise.

Exemplos conhecidos:

```text
@anthropic-ai/claude-code
@openai/codex
@google/gemini-cli
```

Não assumir que todos continuam usando npm: validar documentação oficial.

### Categoria C — instalador/binário próprio

Cursor, OpenCode, Grok, Hermes, Qwen, Kimi ou outros podem possuir distribuição própria.

Nestes casos:

- manter instalador separado;
- verificar fonte oficial;
- permitir atualização através de task;
- não forçar artificialmente o uso de npm.

---

## 69. Diretório de CLIs atualizáveis

Ferramentas atualizáveis não devem depender de camada imutável da imagem quando isso impedir upgrades rápidos.

Utilizar diretório persistente, por exemplo:

```text
/home/orca/.local
```

Garantir PATH:

```text
/home/orca/.local/bin
/home/orca/.local/share/mise/shims
```

antes dos caminhos globais quando apropriado.

---

## 70. Tasks mise

Criar tasks:

```text
agents:update
agents:versions
agents:doctor
```

Uso:

```bash
mise run agents:update
mise run agents:versions
mise run agents:doctor
```

Opcionalmente:

```text
agents:update:claude
agents:update:codex
agents:update:gemini
agents:update:cursor
agents:update:opencode
```

---

## 71. agents:update

Deve:

1. atualizar runtimes gerenciados pelo mise quando solicitado;
2. atualizar cada AI CLI pelo mecanismo oficial;
3. continuar processando agentes independentes quando um opcional falhar;
4. apresentar resumo final;
5. retornar status útil;
6. não apagar credenciais;
7. não modificar `/workspace`.

Saída conceitual:

```text
Updating Claude...
Claude 2.x -> 2.y [OK]

Updating Codex...
Codex x -> y [OK]

Updating Gemini...
Gemini x -> y [OK]

Updating Cursor...
[OK]

Updating Hermes...
[SKIP - disabled]
```

---

## 72. Política de atualização

AI CLIs mudam rapidamente.

Portanto separar:

### Base relativamente estável

```text
Debian
bibliotecas Linux
Orca runtime
mise
```

### Ferramentas de alta frequência

```text
Claude Code
Codex
Gemini CLI
Cursor CLI
OpenCode
Grok
Hermes
Qwen
Kimi
```

As ferramentas de alta frequência devem poder ser atualizadas sem rebuild completo.

---

## 73. Atualização automática

Adicionar:

```text
AUTO_UPDATE_AGENTS=false
```

Default obrigatório:

```text
false
```

Se:

```text
AUTO_UPDATE_AGENTS=true
```

o entrypoint pode executar:

```bash
mise run agents:update
```

antes do Orca.

Porém falha em atualização de agente opcional não deve impedir Orca de iniciar.

Registrar claramente no log.

---

## 74. Atualização manual recomendada

Fluxo recomendado:

```bash
docker exec -it orca-server bash
mise run agents:update
```

ou:

```bash
docker compose exec orca mise run agents:update
```

Isso permite decidir quando atualizar.

---

## 75. Canal stable/latest

Quando a ferramenta suportar, permitir configuração individual.

Exemplo:

```text
CLAUDE_CHANNEL=latest
CODEX_CHANNEL=latest
GEMINI_CHANNEL=latest
CURSOR_CHANNEL=latest
```

Ou versões específicas:

```text
CLAUDE_VERSION=x.y.z
```

Não assumir que todos os agentes usam o mesmo conceito de channel.

---

## 76. Rollback

Antes de atualizar um agente, quando tecnicamente possível, registrar versão atual.

Criar:

```text
/home/orca/.local/state/orca-agent-manager/
```

Registrar histórico:

```text
agent
old_version
new_version
timestamp
result
```

Se o gerenciador utilizado suportar rollback nativamente, documentar.

Não criar mecanismo complexo próprio quando mise/npm já resolver.

---

## 77. Doctor revisado

`doctor` deve validar também:

```text
[OK] tailscale connectivity
[OK] MagicDNS
[OK] mise
[OK] Node via mise
[OK] Python via mise
[OK] uv
[OK] Orca
[OK] Claude
[OK] Codex
[OK] Gemini
...
```

Também mostrar:

```text
Tailscale hostname
Tailscale IP
Orca port
Workspace
HOME
mise data directory
```

Não imprimir tokens/secrets.

---

## 78. Diagnóstico de portas

Adicionar ferramenta/script:

```text
scripts/ports.sh
```

Mostrar portas escutando dentro do namespace compartilhado.

Exemplo:

```text
PORT   PROCESS
6768   Orca
3000   node
8000   uvicorn
8080   java
```

Pode usar:

```bash
ss -lntp
```

quando disponível.

Isso facilita descobrir servidores iniciados pelos agentes.

---

## 79. Acesso aos previews

README deve explicar:

Se um agente iniciar:

```text
Vite :5173
```

acessar:

```text
http://orca-dev:5173
```

Se iniciar:

```text
FastAPI :8000
```

acessar:

```text
http://orca-dev:8000
```

Se iniciar:

```text
Spring Boot :8080
```

acessar:

```text
http://orca-dev:8080
```

Não é necessário alterar Docker Compose para cada nova porta.

---

## 80. Bancos iniciados no próprio container

Evitar instalar bancos diretamente no `orca-dev`.

Para serviços auxiliares permanentes, preferir containers separados.

Exemplo:

```text
compose
├── tailscale
├── orca
├── postgres
├── redis
└── ...
```

Se esses serviços precisarem ser acessados diretamente pela Tailnet, projetar conscientemente o networking.

Não colocar tudo no mesmo container apenas para compartilhar o IP.

---

## 81. Containers criados durante desenvolvimento

Os agentes podem precisar executar Docker.

Manter a decisão anterior:

**não montar `/var/run/docker.sock` por padrão.**

Criar opção explícita/perfil.

Exemplo:

```bash
docker compose --profile docker-access up -d
```

Avaliar socket proxy ou ambiente isolado.

Documentar que montar o socket dá poder equivalente a root no host.

---

## 82. Orca + Tailscale

O Orca deve anunciar endereço alcançável pelo cliente.

Como `orca` compartilha o namespace do Tailscale, usar o IP/hostname correto da Tailnet quando necessário.

Não hardcodar IP.

O entrypoint deve poder descobrir o IPv4 do Tailscale de forma confiável, preferencialmente via:

```bash
tailscale ip -4
```

Porém, como o CLI `tailscale` está no sidecar e pode não existir dentro do container Orca, avaliar uma destas opções:

1. montar socket do `tailscaled` somente se oficialmente suportado;
2. fornecer `ORCA_PAIRING_ADDRESS`;
3. usar hostname MagicDNS;
4. mecanismo oficial documentado pelo Orca/Tailscale.

Preferir a solução mais simples e segura.

Não criar dependência frágil entre containers.

---

## 83. Healthchecks da stack

### Tailscale

Healthcheck deve confirmar que `tailscaled` está operacional/conectado usando mecanismo oficial disponível.

### Orca

Somente iniciar após networking necessário estar disponível quando isso for requisito real.

Não criar loop infinito silencioso.

Adicionar timeout e mensagens claras.

---

## 84. Compose final esperado

O Compose deve suportar aproximadamente:

```text
services:
  tailscale
  orca

volumes:
  tailscale-state
  orca-home
  workspace
```

E opcionalmente profiles:

```text
docker-access
```

Não publicar portas públicas por padrão.

---

## 85. Variáveis finais

`.env.example` deve prever:

```text
# Orca
ORCA_VERSION=
ORCA_PORT=6768
ORCA_PAIRING_ADDRESS=

# Tailscale
TAILSCALE_VERSION=latest
TAILSCALE_HOSTNAME=orca-dev
TS_AUTHKEY=

# Runtime
MISE_VERSION=
NODE_VERSION=22
PYTHON_VERSION=
UV_VERSION=latest

# Updates
AUTO_UPDATE_AGENTS=false

# Agents
INSTALL_CLAUDE=true
INSTALL_CODEX=true
INSTALL_GEMINI=true
INSTALL_CURSOR=true
INSTALL_OPENCODE=true
INSTALL_GROK=false
INSTALL_HERMES=false
INSTALL_QWEN=false
INSTALL_KIMI=false
```

Versões/defaults exatos devem ser confirmados na implementação.

---

## 86. Critérios de aceite adicionais — mise

- [ ] `mise --version` funciona;
- [ ] Node é fornecido pelo mise;
- [ ] Python é fornecido pelo mise quando aplicável;
- [ ] `mise run agents:update` funciona;
- [ ] atualização de Claude não requer rebuild;
- [ ] atualização de Codex não requer rebuild;
- [ ] atualização de Gemini não requer rebuild;
- [ ] versões sobrevivem ao restart;
- [ ] credenciais sobrevivem às atualizações;
- [ ] atualização de um agente não destrói os demais.

---

## 87. Critérios de aceite adicionais — Tailscale

- [ ] sidecar aparece na Tailnet;
- [ ] identidade sobrevive ao restart;
- [ ] MagicDNS resolve `orca-dev`;
- [ ] Orca é acessível pela Tailnet;
- [ ] porta 3000 aberta pelo projeto é acessível;
- [ ] porta 8000 aberta pelo projeto é acessível;
- [ ] porta 8080 aberta pelo projeto é acessível;
- [ ] nova porta aleatória de desenvolvimento não exige rebuild/edição do Compose;
- [ ] nenhuma dessas portas fica pública na Internet por padrão;
- [ ] ACL/grants podem restringir acesso.

---

## 88. Teste obrigatório de portas dinâmicas

Dentro do `orca-dev`:

```bash
python -m http.server 9123 --bind 0.0.0.0
```

De outro dispositivo da Tailnet:

```text
http://orca-dev:9123
```

deve responder.

Depois testar outra porta sem alterar Compose:

```bash
python -m http.server 9876 --bind 0.0.0.0
```

Acessar:

```text
http://orca-dev:9876
```

Esse teste comprova o requisito principal de previews/serviços dinâmicos.

---

## 89. Teste obrigatório de atualização sem rebuild

1. subir stack;
2. registrar versões dos agentes;
3. executar `mise run agents:update`;
4. verificar novas versões quando houver;
5. confirmar Orca continua funcionando;
6. confirmar autenticações;
7. confirmar workspace;
8. reiniciar container;
9. confirmar versões atualizadas persistidas;
10. confirmar que nenhuma imagem precisou ser reconstruída.

---

## 90. Nova ordem de implementação

### Fase A — Docker base

1. Debian Slim.
2. usuário `orca`.
3. dependências mínimas.
4. volumes.

### Fase B — mise

5. instalar mise.
6. PATH correto.
7. Node.
8. Python.
9. uv.
10. tasks básicas.

### Fase C — Orca

11. instalar/extrair Orca.
12. wrapper.
13. Xvfb somente se necessário.
14. validar `orca serve`.

### Fase D — Tailscale

15. sidecar oficial.
16. estado persistente.
17. autenticação.
18. MagicDNS.
19. namespace compartilhado.
20. testar porta Orca.
21. testar portas dinâmicas.

### Fase E — agentes principais

22. Claude.
23. Codex.
24. Gemini.
25. Cursor.
26. OpenCode.

### Fase F — atualização

27. `agents:update`.
28. `agents:versions`.
29. `agents:doctor`.
30. persistência.
31. rollback/documentação.

### Fase G — agentes adicionais

32. Grok.
33. Hermes.
34. Qwen.
35. Kimi.

Somente instalar após confirmação da integração/distribuição oficial.

### Fase H — segurança/qualidade

36. ACL/grants.
37. secrets.
38. healthchecks.
39. ports script.
40. README.
41. testes completos.

---

## 91. Resultado arquitetural final

O resultado deve se comportar como uma **workstation de desenvolvimento remota e persistente**:

```text
                ┌─────────────────────┐
                │ Notebook / Desktop  │
                │ Orca IDE            │
                │ Browser             │
                └─────────┬───────────┘
                          │
                       Tailscale
                          │
                ┌─────────▼───────────┐
                │ orca-dev            │
                │ Tailnet node        │
                │                     │
                │ :6768 Orca          │
                │ :3000 Frontend      │
                │ :5173 Vite          │
                │ :8000 API           │
                │ :8080 Java          │
                │ :xxxx qualquer dev  │
                └─────────┬───────────┘
                          │
                 shared net namespace
                          │
                ┌─────────▼───────────┐
                │ Debian Slim         │
                │ Orca Server         │
                │ mise                │
                │ AI Agents           │
                │ Git/worktrees       │
                │ /workspace          │
                └─────────────────────┘
```

Características obrigatórias:

- ambiente enxuto;
- Debian Slim;
- Orca headless;
- mise como camada de gerenciamento/atualização;
- AI CLIs atualizáveis sem rebuild completo;
- Tailscale sidecar;
- acesso privado a portas dinâmicas;
- nenhuma necessidade de declarar previamente cada porta de desenvolvimento;
- persistência de HOME/workspaces/Tailscale;
- sem exposição pública por padrão;
- sem container privilegiado para Orca;
- sem Docker socket por padrão;
- adequado para Dokploy/Docker Compose.
