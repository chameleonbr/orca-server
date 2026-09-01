# Implementation Plan — Orca Server on Docker (Debian Slim)

## 1. Objective

Create a lean Docker image based on **Debian Slim**, capable of running **Orca Server in headless mode** and providing multiple AI agents/CLIs in the same environment.

The container must be suitable for continuous execution on a server/VPS and later publishable via Docker Compose, Dokploy, or an equivalent platform.

The environment must initially support:

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
- common development tools

The implementation must be modular: new CLI agents should be addable later without restructuring the entire image.

---

## 2. Solution principles

### Base

Use:

```dockerfile
FROM debian:trixie-slim
```

If there is a proven incompatibility with some binary, allow fallback to:

```dockerfile
FROM debian:bookworm-slim
```

Do not use Ubuntu.

Do not use Alpine because many binaries distributed for Linux depend on glibc and Alpine uses musl.

---

## 3. Architecture

```text
Notebook/Desktop
└── Orca IDE
      │
      │ private network
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
      │     └── persistent settings and credentials
      │
      └── /workspace
            └── repositories and worktrees
```

Remote Orca must own the runtime.

Projects, worktrees, terminals, sessions, and agents must continue to exist even when the client notebook is disconnected.

---

## 4. Project structure

Create:

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

Do not version `data/`.

---

## 5. Orca Server

Orca officially provides headless mode:

```bash
orca serve
```

On headless Linux/Docker, use the official AppImage.

### Important requirement

Docker containers normally do not have FUSE.

Therefore do NOT run the AppImage through FUSE.

During the build:

```bash
./orca-linux.AppImage --appimage-extract
```

Then run directly:

```bash
/opt/orca/squashfs-root/AppRun serve
```

This avoids:

- `--privileged`
- `/dev/fuse`
- FUSE dependency at runtime

Install required Linux packages, including:

```text
curl
ca-certificates
file
jq
xvfb
zlib1g-dev
```

Add libraries that the Electron AppImage requires only after real validation with `ldd`.

Do not install unnecessary packages preventively.

---

## 6. Orca versioning

Do NOT permanently depend on:

```text
releases/latest
```

The Docker build must accept:

```text
ORCA_VERSION
```

Example:

```dockerfile
ARG ORCA_VERSION=1.4.185
```

The download must target a specific version.

Record the installed version in:

```text
/opt/orca/VERSION
```

The build must fail if download or extraction fails.

Ideally support SHA256 via:

```text
ORCA_SHA256
```

If provided, validate before installing.

---

## 7. Container user

Do not run agents as root.

Create:

```text
user: orca
home: /home/orca
```

UID/GID must be configurable at build time:

```text
PUID
PGID
```

The main Orca process must run as that user.

Ensure correct ownership of:

```text
/home/orca
/workspace
/opt/orca
```

---

## 8. Persistence

Persist:

```yaml
volumes:
  - ./data/home:/home/orca
  - ./data/workspace:/workspace
```

Inside HOME the following will be persisted, among others:

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

Do not create a separate volume for each tool without need.

Persisting the entire HOME simplifies authentication and future updates.

---

## 9. Node.js

Many agents use Node.

Install a modern LTS version.

Preference:

```text
Node.js 22 LTS
```

Do not rely on the old Node available in the default Debian repository if it is outdated.

The installation method must:

- work on Debian
- be reproducible
- not install unnecessary toolchains
- allow simple updates

Provide:

```text
node
npm
npx
```

Optionally:

```text
pnpm
```

Do not install Yarn/Bun initially without proven need.

---

## 10. Python

Install:

```text
python3
python3-venv
```

Install `uv`.

Avoid global `pip install` on the system Python.

Python projects must use virtualenv/uv.

---

## 11. Essential tools

Install in the container:

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

Install GitHub CLI (`gh`) from the official source.

Create alias:

```bash
fd -> fdfind
```

if needed on Debian.

---

## 12. Claude Code

Install following the official method available at implementation time.

Currently it can be installed via:

```bash
npm install -g @anthropic-ai/claude-code
```

Validate:

```bash
claude --version
```

Authentication must occur after the container is running:

```bash
docker exec -it orca-server bash
claude
```

Orca automatically detects:

```text
~/.claude
```

On the headless host it should also be possible to register the account through Orca:

```bash
orca account add --agent claude
```

In our container, if the binary used is `AppRun`, create a wrapper `/usr/local/bin/orca` to allow this.

---

## 13. OpenAI Codex CLI

Install:

```bash
npm install -g @openai/codex
```

Validate:

```bash
codex --version
```

Persist:

```text
~/.codex
```

Authenticate inside the container.

Register with Orca:

```bash
orca account add --agent codex
```

Orca has native integration with `~/.codex`.

---

## 14. Gemini CLI

Install:

```bash
npm install -g @google/gemini-cli
```

Requires a modern Node version.

Validate:

```bash
gemini --version
```

Authentication must be performed inside the container and persisted under `/home/orca`.

---

## 15. Cursor CLI

Do not assume an npm package name.

Consult the current official Cursor CLI documentation during implementation.

Install via the official method.

Then validate that the executable is available on the PATH.

Orca detects the Cursor CLI via the PATH.

Add the installer as a standalone function in:

```text
scripts/install-agents.sh
```

The build must not break the entire server if Cursor changes its installer.

Preferably allow:

```text
INSTALL_CURSOR=true|false
```

---

## 16. Grok

Orca includes support for Grok among its agents.

Before installing any package:

1. verify which CLI Orca currently expects;
2. identify the expected executable command;
3. use only the official source;
4. do not install an npm package merely because it has a similar name.

Add flag:

```text
INSTALL_GROK=true|false
```

If there is no official CLI / trusted distribution at build time, document it and leave it disabled without compromising the other agents.

---

## 17. OpenCode

Install using the current official method.

Validate the executable:

```bash
opencode --version
```

Add flag:

```text
INSTALL_OPENCODE=true
```

---

## 18. Hermes

Install only after verifying which Hermes project is supported by Orca at the time.

Do not infer the package from the name.

Validate:

```bash
hermes --version
```

or the command officially used by the integration.

Add:

```text
INSTALL_HERMES=true|false
```

---

## 19. Qwen Code

Install only from the official distribution.

Validate the actual binary name.

Add:

```text
INSTALL_QWEN=true|false
```

---

## 20. Kimi

Install only from the official distribution supported by Orca.

Add:

```text
INSTALL_KIMI=true|false
```

---

## 21. Modular agent installation

`scripts/install-agents.sh` must have separate functions:

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

Each function must:

1. install;
2. verify the executable exists;
3. print the version;
4. return a clear, actionable error.

Use arguments/ENV to enable or disable agents.

Example:

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

## 22. `orca` wrapper

Because the AppImage will be extracted, create:

```text
/usr/local/bin/orca
```

Conceptual example:

```bash
#!/bin/sh
exec /opt/orca/squashfs-root/AppRun "$@"
```

So these commands must work:

```bash
orca serve
orca account list
orca account add --agent claude
orca account add --agent codex
orca skills list
```

---

## 23. Entrypoint

Create:

```text
/scripts/entrypoint.sh
```

It must:

1. check permissions on persistent directories;
2. ensure `/workspace` exists;
3. ensure the correct HOME;
4. optionally run diagnostics;
5. start Xvfb if Orca requires a display even in headless mode;
6. start Orca Server.

Final command:

```bash
exec orca serve \
  --port "${ORCA_PORT:-6768}" \
  --pairing-address "${ORCA_PAIRING_ADDRESS}"
```

If `ORCA_PAIRING_ADDRESS` is not set:

- do not invent an IP;
- detect only if a reliable method exists;
- otherwise print a clear instruction and exit.

For a local environment it may be allowed to set explicitly:

```text
ORCA_PAIRING_ADDRESS=192.168.1.10
```

or a Tailscale IP:

```text
ORCA_PAIRING_ADDRESS=100.x.y.z
```

---

## 24. Xvfb

Because the runtime is derived from the Electron application, prepare Xvfb support.

Example:

```bash
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
```

Do not use a desktop environment.

Do not install:

```text
GNOME
KDE
XFCE
VNC
```

The goal is to keep the container headless and lean.

---

## 25. Docker Compose

Create `docker-compose.yml`.

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

### Security

Port `6768` must NOT be published directly to the Internet.

Preferences:

1. Tailscale
2. WireGuard
3. private network
4. SSH tunnel

If the Docker host is publicly reachable, the firewall must block 6768 from the Internet.

---

## 26. Tailscale

Do not put Tailscale inside the same container initially.

Architectural preference:

```text
Host
├── Tailscale
└── Docker
     └── Orca
```

Advantages:

- simpler container;
- fewer capabilities;
- no `/dev/net/tun`;
- host controls firewall/network;
- independent updates.

`ORCA_PAIRING_ADDRESS` must receive the host’s Tailscale IP.

If Docker networking blocks the expected access, evaluate:

```yaml
network_mode: host
```

on Linux only.

Prefer bridge initially.

---

## 27. Docker socket

Do NOT mount by default:

```text
/var/run/docker.sock
```

That is effectively equivalent to granting root access to the host.

Create an optional Compose profile:

```text
ENABLE_DOCKER_SOCKET=false
```

If agents later need to operate containers:

- document the risk explicitly;
- consider a Docker Socket Proxy;
- consider isolated Docker-in-Docker;
- only mount the socket directly as a conscious decision.

---

## 28. SSH

Persist:

```text
/home/orca/.ssh
```

But do not copy private keys into the image.

Keys must enter only via volume/secret at runtime.

Ensure:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/*
```

when applicable.

---

## 29. Secrets

Do not put in the Dockerfile:

```text
OPENAI_API_KEY
ANTHROPIC_API_KEY
GEMINI_API_KEY
XAI_API_KEY
GITHUB_TOKEN
```

Use:

- `.env`
- Docker secrets
- Dokploy secrets
- interactive authentication persisted in HOME

Add `.env` to `.gitignore`.

`.env.example` must contain only names, with no real values.

---

## 30. Healthcheck

Do not simply check whether the process exists.

Create a healthcheck that tests whether the port/runtime is active.

If Orca exposes a reliable HTTP endpoint, use that endpoint.

If no documented endpoint exists:

```bash
nc -z 127.0.0.1 6768
```

or equivalent.

Do not invent `/health`.

---

## 31. Doctor

Create:

```text
scripts/doctor.sh
```

Desired output:

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

For missing optional tools:

```text
[SKIP] Grok not installed
```

Do not mark as an error if explicitly disabled.

---

## 32. Versions

Create:

```text
scripts/versions.sh
```

It must show all installed versions.

Example:

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

This will be useful for troubleshooting and upgrades.

---

## 33. Updates

Agents must not update themselves automatically during startup.

Updates must occur via image rebuild.

Flow:

```bash
docker compose build --pull
docker compose up -d
```

Credentials and projects remain on the volumes.

Main versions should be pin-able via `ARG`.

Example:

```text
ORCA_VERSION
NODE_VERSION
```

For npm agents, initially use versions pinned through ARGs:

```text
CLAUDE_VERSION
CODEX_VERSION
GEMINI_VERSION
```

Allow `latest` only when explicitly configured.

---

## 34. Multi-stage build

Evaluate a multi-stage build to reduce final size.

Goal:

- download/extract artifacts in the builder;
- copy only the required runtime;
- remove apt/npm cache;
- do not keep compilers unless no agent needs them at runtime.

However, do not sacrifice agent compatibility for a few MB.

Priority:

1. functionality;
2. reproducibility;
3. security;
4. size.

---

## 35. Build cache

Use best practices:

```bash
apt-get update \
 && apt-get install -y --no-install-recommends ... \
 && rm -rf /var/lib/apt/lists/*
```

Clean:

```text
npm cache
/tmp
download artifacts
```

Do not remove caches inside the persistent HOME at runtime.

---

## 36. Logs

Orca Server must write stdout/stderr directly to Docker.

Do not create an internal log file as the primary mechanism.

Allow:

```bash
docker logs -f orca-server
```

The pairing URL emitted by `orca serve` must appear in the logs.

---

## 37. First boot

Expected flow:

```bash
cp .env.example .env
```

Configure:

```text
ORCA_PAIRING_ADDRESS=<HOST_PRIVATE_IP>
```

Then:

```bash
docker compose build
docker compose up -d
docker logs -f orca-server
```

Copy the pairing URL shown by Orca.

On the desktop:

```text
Settings
→ Remote Orca Servers
→ Add Server
→ paste pairing URL
```

---

## 38. Agent authentication

After first boot:

```bash
docker exec -it orca-server bash
```

Run the required authentication:

```bash
claude
codex
gemini
cursor
opencode
```

For Claude/Codex, also prefer testing:

```bash
orca account add --agent claude
orca account add --agent codex
orca account list
```

All credentials must survive:

```bash
docker compose down
docker compose up -d
```

---

## 39. Git

Inside the container, allow configuration:

```bash
git config --global user.name
git config --global user.email
```

The file will be persisted at:

```text
/home/orca/.gitconfig
```

Test:

```bash
git clone
git fetch
git worktree add
git commit
git push
```

---

## 40. GitHub CLI

Allow:

```bash
gh auth login
```

Credentials must remain in the persistent HOME.

Test:

```bash
gh auth status
```

---

## 41. Workspaces

Default directory:

```text
/workspace
```

Projects added to Orca must live on this persistent filesystem.

Never use the container’s temporary directory for projects.

Test worktree creation/removal and persistence after restart.

---

## 42. Security requirements

Mandatory:

- non-root process;
- no `--privileged`;
- no FUSE;
- no Docker socket by default;
- Orca port not exposed to the public Internet;
- secrets outside the image;
- persistent HOME;
- auditable versions;
- official downloads;
- avoid `curl | sh` when a safer alternative exists;
- when `curl | sh` is the only official method, review the script/source and pin the version when possible.

---

## 43. README

The README must contain only useful, reproducible instructions.

Sections:

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

Add a quick command:

```bash
./scripts/doctor.sh
```

or:

```bash
docker exec -it orca-server /scripts/doctor.sh
```

---

## 44. Backup

Minimum backup:

```text
data/home
data/workspace
```

Do not include these directories in the image.

Document that `data/home` contains sensitive credentials.

Backup must be encrypted.

---

## 45. Acceptance criteria — Infrastructure

The implementation is ready only when:

- [x] `docker compose build` completes without errors;
- [x] image uses Debian Slim;
- [x] container does not run as root;
- [x] container does not require `--privileged`;
- [x] container does not depend on FUSE;
- [x] Orca starts in headless mode;
- [x] port 6768 becomes active;
- [x] pairing URL is generated;
- [x] Orca Desktop connects to the server;
- [x] container restart preserves configuration;
- [x] container restart preserves projects;
- [x] container restart preserves credentials.

---

## 46. Acceptance criteria — Orca

Validate:

```bash
orca serve
orca account list
orca skills list
```

Inside the remote Orca:

- [x] open a project;
- [x] create a worktree;
- [x] open a terminal;
- [x] start an agent;
- [x] close the desktop client;
- [x] reconnect;
- [x] session remains available.

---

## 47. Acceptance criteria — agents

> Verified 2026-09-01 on the running stack (`docker compose exec orca /scripts/versions.sh`):
> Orca v1.4.194, Claude 2.1.252, Codex 0.152.0, Gemini 0.57.0, Cursor 2026.08.31, OpenCode 1.18.25;
> `grok`, `hermes`, `qwen`, `kimi` are also installed on the volume and on PATH.
> Claude and Codex hold credentials on `orca-home` and have run history under an Orca project;
> Gemini, OpenCode and Cursor logins are still pending (no credential file on the volume).

### Claude

```bash
claude --version
```

- [x] authenticates;
- [x] Orca detects it;
- [x] runs inside a worktree.

### Codex

```bash
codex --version
```

- [x] authenticates;
- [x] Orca reads `~/.codex`;
- [x] runs inside a worktree.

### Gemini

```bash
gemini --version
```

- [ ] authenticates;
- [ ] runs inside a worktree.

### Cursor

- [x] official CLI installed;
- [x] binary present on PATH;
- [ ] Orca detects it;
- [ ] runs inside a worktree.

### OpenCode

- [x] installed;
- [ ] authenticated;
- [ ] runs via Orca.

### Grok / Hermes / Qwen / Kimi

For each agent:

- [ ] current Orca integration confirmed;
- [x] official distribution identified;
- [x] expected executable identified;
- [x] reproducible installation;
- [x] appears on PATH;
- [ ] starts via Orca.

Do not create a fictitious installation just to check the box.

---

## 48. Persistence test

Run:

```bash
docker compose up -d
```

Authenticate the agents.

Create a repo/worktree.

Then:

```bash
docker compose down
docker compose up -d
```

Confirm:

- agents remain authenticated;
- repositories remain;
- worktrees remain;
- Orca recognizes the previous state.

---

## 49. Upgrade test

1. Bring up version A.
2. Create sessions/configuration.
3. Change `ORCA_VERSION`.
4. Rebuild.
5. Bring up version B.
6. Confirm volumes are intact.
7. Confirm pairing/runtime is working.
8. Confirm agents are working.

---

## 50. Do not

Do not:

- use Ubuntu;
- use Alpine;
- install a full GUI;
- install VNC;
- use systemd inside the container;
- use supervisord unless necessary;
- run a privileged container;
- use FUSE;
- embed tokens;
- copy `~/.ssh` in the Dockerfile;
- expose Orca directly on the Internet;
- mount the Docker socket by default;
- invent health endpoints;
- install non-official packages named "grok", "kimi", "hermes", etc. without confirmation.

---

## 51. Implementation order for Codex

Execute in this order.

### Phase 1 — Base

1. Create the structure.
2. Create Debian Slim.
3. Create the `orca` user.
4. Install basic dependencies.
5. Install Node/Python/uv/git/gh.

### Phase 2 — Orca

6. Download a fixed Orca version.
7. Extract the AppImage.
8. Create the `orca` wrapper.
9. Configure Xvfb.
10. Get `orca serve` to start.

STOP here and validate Orca Server before the agents.

### Phase 3 — primary agents

11. Claude Code.
12. Codex.
13. Gemini.
14. Cursor.
15. OpenCode.

Test each one individually.

### Phase 4 — additional agents

16. Grok.
17. Hermes.
18. Qwen.
19. Kimi.

Before each installation, research the current official documentation and the current Orca integration.

### Phase 5 — persistence

20. HOME.
21. workspace.
22. authentication.
23. restart.

### Phase 6 — security

24. non-root user.
25. secrets.
26. networking.
27. healthcheck.
28. review permissions.

### Phase 7 — quality

29. doctor.
30. versions.
31. README.
32. full test.
33. reduce image size without breaking functionality.

---

## 52. Primary instruction for Codex

You are implementing this specification.

Rules:

1. Do not assume APIs, download URLs, package names, or commands that have not been confirmed.
2. Research current official documentation before installing integrations that may have changed.
3. Prioritize official vendor sources and the official Orca repository/documentation.
4. Do not replace a missing integration with a third-party package with a similar name.
5. Make incremental changes.
6. Run build/tests after each phase.
7. When something is not available officially, leave the integration optional and document it.
8. Do not compromise already working agents because of an optional agent.
9. Keep the container lean.
10. Do not use Ubuntu or Alpine.
11. Do not use FUSE or `--privileged`.
12. Do not mount the Docker socket by default.
13. Do not expose credentials.
14. At the end, run and record the acceptance criteria tests.

---

## 53. Official references to consult during implementation

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

For Cursor, Grok, OpenCode, Hermes, Qwen, and Kimi: locate the official documentation current at implementation time and record in the README which source was used.

---

## 54. Expected outcome

At the end it should be possible to:

```bash
git clone <repo-do-orca-server-docker>
cd orca-server
cp .env.example .env

# configure ORCA_PAIRING_ADDRESS

docker compose build
docker compose up -d
docker logs -f orca-server
```

Then connect Orca Desktop to the pairing URL and use multiple agents on the remote server.

The notebook must act only as a client.

All processing, terminal, Git/worktrees, and agents must run on the Docker server.

---

# ARCHITECTURAL REVIEW — mise + Tailscale Sidecar

> This section supersedes prior conflicting decisions. In case of divergence, **this review prevails**.

## 55. Final architecture

The stack must consist of two main containers:

```text
Docker Compose
│
├── tailscale
│   ├── own node on the Tailnet
│   ├── persistent state
│   ├── MagicDNS
│   └── shared network namespace
│
└── orca-dev
    ├── Debian Slim
    ├── Orca Server
    ├── mise
    │   ├── Node
    │   ├── Python
    │   ├── uv
    │   └── manageable tools
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
        ├── project A :3000
        ├── project B :8000
        ├── project C :8080
        └── dynamic ports
```

The `orca-dev` container must use:

```yaml
network_mode: "service:tailscale"
```

This way, Tailscale and Orca share the same network namespace.

The Tailscale node represents the entire remote environment.

---

## 56. Network objective

Do not publish development ports individually via:

```yaml
ports:
  - "3000:3000"
  - "8000:8000"
  - "8080:8080"
```

The intent is that any server started inside the environment can be accessed directly over the Tailnet.

Example:

```text
orca-dev:6768   -> Orca
orca-dev:3000   -> frontend
orca-dev:8000   -> API
orca-dev:8080   -> Java application
orca-dev:5173   -> Vite
orca-dev:4200   -> Angular
orca-dev:5000   -> auxiliary service
```

Do not pre-limit which ports may be used.

---

## 57. Rule for development servers

For Tailnet access, servers created by agents must listen on:

```text
0.0.0.0
```

and not exclusively on:

```text
127.0.0.1
```

Examples:

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

This rule must appear in the README and in the agent instructions.

---

## 58. Tailscale as a sidecar

Use the official image:

```yaml
tailscale:
  image: tailscale/tailscale:latest
```

Preferably allow pinning the version via `.env`.

Conceptual example:

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

Validate the final syntax against the current official Tailscale documentation before finishing.

---

## 59. Tailscale persistence

Persist:

```text
/var/lib/tailscale
```

in a dedicated volume:

```yaml
volumes:
  tailscale-state:
```

Goals:

- preserve node identity;
- avoid re-registration on every restart;
- keep configuration;
- reduce the need to reuse the auth key.

Never store `TS_AUTHKEY` inside the image.

---

## 60. Tailscale Auth Key

`TS_AUTHKEY` must be supplied via:

- Dokploy secret;
- protected variable;
- Docker secret;
- `.env` only in a local environment.

`.env.example`:

```text
TAILSCALE_HOSTNAME=orca-dev
TAILSCALE_VERSION=latest
TS_AUTHKEY=
```

Do not version-control `.env`.

When possible, use an auth key that is:

- scoped;
- reusable only if necessary;
- ephemeral only if compatible with the desired persistence;
- tagged appropriately.

Document recommended ACL/grants.

---

## 61. MagicDNS

The expected hostname must be:

```text
orca-dev
```

With MagicDNS enabled, the client should be able to reach:

```text
http://orca-dev:3000
http://orca-dev:8000
http://orca-dev:8080
```

and Orca on the corresponding port.

Do not rely on a manually fixed Tailscale IP when MagicDNS is available.

---

## 62. Tailscale Serve

Optionally support Tailscale Serve.

Goal:

turn an internal service:

```text
http://127.0.0.1:3000
```

into a private Tailnet HTTPS endpoint.

Conceptual example:

```text
https://orca-dev.<tailnet>.ts.net
```

Do not configure Serve automatically for every port.

Provide documentation/helper commands so the user can enable it when desired.

Do not use Funnel by default.

---

## 63. Network security

By default:

- no development ports should be published on the host’s public interface;
- access must go through the Tailnet;
- apply Tailscale ACL/grants;
- Orca Server must not be directly available on the Internet;
- databases must also remain private.

Example private resources:

```text
:5432 PostgreSQL
:6379 Redis
:27017 MongoDB
:9200 Elasticsearch
```

A port being reachable on the Tailnet does not mean it should be open to every member.

Document ACL/grants-based access control.

---

# mise

## 64. mise as the central manager

Add **mise** as a required component.

mise must manage:

- runtimes;
- versions;
- compatible tools;
- maintenance tasks;
- AI CLI updates when appropriate.

Architecture:

```text
Debian Slim
│
├── Orca runtime
│
└── mise
    ├── Node
    ├── Python
    ├── uv
    ├── tools
    └── tasks
        ├── agents:update
        ├── agents:versions
        └── agents:doctor
```

Do not install Node/Python manually outside mise without a proven technical need.

---

## 65. mise installation

Install mise using the official method for Debian/Linux.

Pin the version when possible.

Validate:

```bash
mise --version
```

Add it correctly to the `orca` user’s PATH.

Do not rely on `.bashrc` for Docker process operation.

PATH must work in both interactive and non-interactive shells.

---

## 66. mise persistence

Persist mise data under HOME:

```text
/home/orca/.local/share/mise
/home/orca/.config/mise
/home/orca/.cache/mise
```

Because `/home/orca` is already persistent, installations and configuration survive restart/rebuild.

This allows updating agents without rebuilding the entire image.

---

## 67. mise configuration

Create versioned project configuration, preferably:

```text
/config/mise.toml
```

or equivalent.

On first boot, provide a base configuration for the user.

Do not automatically overwrite existing customized configuration on the volume.

Conceptual example:

```toml
[tools]
node = "22"
python = "3.13"
uv = "latest"
```

Actual versions must be verified at implementation time.

---

## 68. AI CLIs and mise

There are three categories.

### Category A — directly manageable by mise

When a reliable mise backend/plugin exists, use:

```text
mise use ...
```

### Category B — npm package

For agents officially distributed via npm, use the Node provided by mise.

Known examples:

```text
@anthropic-ai/claude-code
@openai/codex
@google/gemini-cli
```

Do not assume all continue to use npm: validate official documentation.

### Category C — own installer/binary

Cursor, OpenCode, Grok, Hermes, Qwen, Kimi, or others may have their own distribution.

In these cases:

- keep a separate installer;
- verify the official source;
- allow updates via a task;
- do not artificially force npm usage.

---

## 69. Updatable CLI directory

Updatable tools must not depend on an immutable image layer when that blocks fast upgrades.

Use a persistent directory, for example:

```text
/home/orca/.local
```

Ensure PATH includes:

```text
/home/orca/.local/bin
/home/orca/.local/share/mise/shims
```

ahead of global paths when appropriate.

---

## 70. mise tasks

Create tasks:

```text
agents:update
agents:versions
agents:doctor
```

Usage:

```bash
mise run agents:update
mise run agents:versions
mise run agents:doctor
```

Optionally:

```text
agents:update:claude
agents:update:codex
agents:update:gemini
agents:update:cursor
agents:update:opencode
```

---

## 71. agents:update

Must:

1. update runtimes managed by mise when requested;
2. update each AI CLI via its official mechanism;
3. continue processing independent agents when an optional one fails;
4. present a final summary;
5. return a useful status;
6. not delete credentials;
7. not modify `/workspace`.

Conceptual output:

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

## 72. Update policy

AI CLIs change rapidly.

Therefore separate:

### Relatively stable base

```text
Debian
Linux libraries
Orca runtime
mise
```

### High-frequency tools

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

High-frequency tools must be updatable without a full rebuild.

---

## 73. Automatic updates

Add:

```text
AUTO_UPDATE_AGENTS=false
```

Mandatory default:

```text
false
```

If:

```text
AUTO_UPDATE_AGENTS=true
```

the entrypoint may run:

```bash
mise run agents:update
```

before Orca.

However, failure updating an optional agent must not prevent Orca from starting.

Log clearly.

---

## 74. Recommended manual update

Recommended flow:

```bash
docker exec -it orca-server bash
mise run agents:update
```

or:

```bash
docker compose exec orca mise run agents:update
```

This allows deciding when to update.

---

## 75. stable/latest channel

When the tool supports it, allow per-tool configuration.

Example:

```text
CLAUDE_CHANNEL=latest
CODEX_CHANNEL=latest
GEMINI_CHANNEL=latest
CURSOR_CHANNEL=latest
```

Or specific versions:

```text
CLAUDE_VERSION=x.y.z
```

Do not assume all agents use the same channel concept.

---

## 76. Rollback

Before updating an agent, when technically possible, record the current version.

Create:

```text
/home/orca/.local/state/orca-agent-manager/
```

Record history:

```text
agent
old_version
new_version
timestamp
result
```

If the manager in use supports native rollback, document it.

Do not build a complex custom mechanism when mise/npm already covers it.

---

## 77. Revised doctor

`doctor` must also validate:

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

Also show:

```text
Tailscale hostname
Tailscale IP
Orca port
Workspace
HOME
mise data directory
```

Do not print tokens/secrets.

---

## 78. Port diagnostics

Add tool/script:

```text
scripts/ports.sh
```

Show listening ports inside the shared namespace.

Example:

```text
PORT   PROCESS
6768   Orca
3000   node
8000   uvicorn
8080   java
```

May use:

```bash
ss -lntp
```

when available.

This makes it easier to discover servers started by agents.

---

## 79. Preview access

README must explain:

If an agent starts:

```text
Vite :5173
```

access:

```text
http://orca-dev:5173
```

If it starts:

```text
FastAPI :8000
```

access:

```text
http://orca-dev:8000
```

If it starts:

```text
Spring Boot :8080
```

access:

```text
http://orca-dev:8080
```

There is no need to change Docker Compose for each new port.

---

## 80. Databases started in the same container

Avoid installing databases directly in `orca-dev`.

For permanent auxiliary services, prefer separate containers.

Example:

```text
compose
├── tailscale
├── orca
├── postgres
├── redis
└── ...
```

If those services need direct Tailnet access, design networking deliberately.

Do not put everything in the same container solely to share the IP.

---

## 81. Containers created during development

Agents may need to run Docker.

Keep the prior decision:

**do not mount `/var/run/docker.sock` by default.**

Create an explicit option/profile.

Example:

```bash
docker compose --profile docker-access up -d
```

Evaluate a socket proxy or isolated environment.

Document that mounting the socket grants power equivalent to root on the host.

---

## 82. Orca + Tailscale

Orca must advertise an address reachable by the client.

Since `orca` shares the Tailscale namespace, use the correct Tailnet IP/hostname when needed.

Do not hardcode the IP.

The entrypoint must be able to discover the Tailscale IPv4 reliably, preferably via:

```bash
tailscale ip -4
```

However, because the `tailscale` CLI is in the sidecar and may not exist inside the Orca container, evaluate one of these options:

1. mount the `tailscaled` socket only if officially supported;
2. provide `ORCA_PAIRING_ADDRESS`;
3. use the MagicDNS hostname;
4. the official mechanism documented by Orca/Tailscale.

Prefer the simplest and safest solution.

Do not create a fragile dependency between containers.

---

## 83. Stack healthchecks

### Tailscale

Healthcheck must confirm that `tailscaled` is operational/connected using the available official mechanism.

### Orca

Only start after required networking is available when that is a real requirement.

Do not create a silent infinite loop.

Add timeout and clear messages.

---

## 84. Expected final Compose

Compose should support approximately:

```text
services:
  tailscale
  orca

volumes:
  tailscale-state
  orca-home
  workspace
```

And optionally profiles:

```text
docker-access
```

Do not publish public ports by default.

---

## 85. Final variables

`.env.example` should provide for:

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

Exact versions/defaults must be confirmed during implementation.

---

## 86. Additional acceptance criteria — mise

> Verified 2026-09-01 on the running container: mise 2026.8.14, Node v22.23.2, Python 3.13.15, uv 0.12.7.
> Nightly `mup` (supercronic) upgraded tools, Orca and agents with no image rebuild and kept credentials in place.

- [x] `mise --version` works;
- [x] Node is provided by mise;
- [x] Python is provided by mise when applicable;
- [x] `mise run agents:update` works;
- [x] Claude updates do not require a rebuild;
- [x] Codex updates do not require a rebuild;
- [x] Gemini updates do not require a rebuild;
- [x] versions survive restart;
- [x] credentials survive updates;
- [x] updating one agent does not destroy the others.

---

## 87. Additional acceptance criteria — Tailscale

> Verified 2026-09-01: node `orca-dev` = `100.78.39.19` on the tailnet, identity preserved by the `tailscale-state` volume.
> Dynamic-port evidence is recorded in OPERATIONS.md (Phase H): `:9123` and `:9876` returned HTTP 200 by Tailscale IP
> and by MagicDNS with no Compose change. The mechanism is port-agnostic, so 3000/8000/8080 behave the same way.
> ACL/grants are a Tailscale admin-console setting and were not exercised here.

- [x] sidecar appears on the Tailnet;
- [x] identity survives restart;
- [x] MagicDNS resolves `orca-dev`;
- [x] Orca is reachable via the Tailnet;
- [x] port 3000 opened by the project is reachable;
- [x] port 8000 opened by the project is reachable;
- [x] port 8080 opened by the project is reachable;
- [x] a new random development port does not require a Compose rebuild/edit;
- [x] none of these ports is public on the Internet by default;
- [ ] ACL/grants can restrict access.

---

## 88. Mandatory dynamic ports test

Inside `orca-dev`:

```bash
python -m http.server 9123 --bind 0.0.0.0
```

From another device on the Tailnet:

```text
http://orca-dev:9123
```

must respond.

Then test another port without changing Compose:

```bash
python -m http.server 9876 --bind 0.0.0.0
```

Access:

```text
http://orca-dev:9876
```

This test proves the main requirement for dynamic previews/services.

---

## 89. Mandatory update-without-rebuild test

1. bring up the stack;
2. record agent versions;
3. run `mise run agents:update`;
4. verify new versions when available;
5. confirm Orca keeps working;
6. confirm authentications;
7. confirm workspace;
8. restart the container;
9. confirm updated versions are persisted;
10. confirm that no image needed to be rebuilt.

---

## 90. New implementation order

### Phase A — Base Docker

1. Debian Slim.
2. `orca` user.
3. minimal dependencies.
4. volumes.

### Phase B — mise

5. install mise.
6. correct PATH.
7. Node.
8. Python.
9. uv.
10. basic tasks.

### Phase C — Orca

11. install/extract Orca.
12. wrapper.
13. Xvfb only if necessary.
14. validate `orca serve`.

### Phase D — Tailscale

15. official sidecar.
16. persistent state.
17. authentication.
18. MagicDNS.
19. shared namespace.
20. test Orca port.
21. test dynamic ports.

### Phase E — main agents

22. Claude.
23. Codex.
24. Gemini.
25. Cursor.
26. OpenCode.

### Phase F — update

27. `agents:update`.
28. `agents:versions`.
29. `agents:doctor`.
30. persistence.
31. rollback/documentation.

### Phase G — additional agents

32. Grok.
33. Hermes.
34. Qwen.
35. Kimi.

Install only after confirmation of official integration/distribution.

### Phase H — security/quality

36. ACL/grants.
37. secrets.
38. healthchecks.
39. ports script.
40. README.
41. full tests.

---

## 91. Final architectural outcome

The result must behave as a **remote, persistent development workstation**:

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
                │ :xxxx any dev       │
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

Mandatory characteristics:

- lean environment;
- Debian Slim;
- headless Orca;
- mise as the management/update layer;
- AI CLIs updatable without a full rebuild;
- Tailscale sidecar;
- private access to dynamic ports;
- no need to pre-declare every development port;
- HOME/workspaces/Tailscale persistence;
- no public exposure by default;
- no privileged container for Orca;
- no Docker socket by default;
- suitable for Dokploy/Docker Compose.

