# syntax=docker/dockerfile:1
# Orca Server headless workstation — Debian Slim + mise + AI agents
# Spec: docs/IMPLEMENTATION_PLAN.md (review mise + Tailscale sidecar prevails)

ARG DEBIAN_CODENAME=trixie
FROM debian:${DEBIAN_CODENAME}-slim

ARG PUID=1000
ARG PGID=1000
ARG ORCA_VERSION=1.4.185
ARG ORCA_SHA256=
ARG MISE_VERSION=
ARG NODE_VERSION=22
ARG PYTHON_VERSION=3.13
ARG UV_VERSION=latest

ARG INSTALL_CLAUDE=true
ARG INSTALL_CODEX=true
ARG INSTALL_GEMINI=true
ARG INSTALL_CURSOR=true
ARG INSTALL_OPENCODE=true
ARG INSTALL_GROK=false
ARG INSTALL_HERMES=false
ARG INSTALL_QWEN=false
ARG INSTALL_KIMI=false

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/orca \
    USER=orca \
    LANG=C.UTF-8 \
    ORCA_PORT=6768 \
    PATH="/home/orca/.local/bin:/home/orca/.local/share/mise/shims:/usr/local/bin:${PATH}"

# --- Phase A: base packages ---
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      wget \
      git \
      openssh-client \
      jq \
      less \
      nano \
      vim-tiny \
      procps \
      psmisc \
      unzip \
      zip \
      tar \
      gzip \
      file \
      ripgrep \
      fd-find \
      fzf \
      build-essential \
      python3 \
      python3-venv \
      xvfb \
      zlib1g-dev \
      netcat-openbsd \
      iproute2 \
      sudo \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf "$(command -v fdfind)" /usr/local/bin/fd || true

# --- non-root user ---
RUN groupadd -g "${PGID}" orca \
 && useradd -m -u "${PUID}" -g "${PGID}" -s /bin/bash -d /home/orca orca \
 && mkdir -p /workspace /opt/orca /scripts \
 && chown -R orca:orca /home/orca /workspace

# --- GitHub CLI (official apt source) ---
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

COPY scripts/ /scripts/
COPY config/mise.toml /opt/orca-server/mise.toml
RUN chmod +x /scripts/*.sh

# --- Phase B: mise (as orca) ---
USER orca
WORKDIR /home/orca

RUN /scripts/install-mise.sh \
 && /scripts/bootstrap-runtimes.sh

# --- Phase C: Orca AppImage extract (no FUSE) ---
USER root
RUN /scripts/install-orca.sh \
 && chown -R orca:orca /opt/orca

# --- Phase E/G: agents (modular flags) ---
USER orca
RUN /scripts/install-agents.sh

USER orca
WORKDIR /workspace

EXPOSE 6768

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD nc -z 127.0.0.1 ${ORCA_PORT:-6768} || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["serve"]
