# syntax=docker/dockerfile:1
# Orca Server headless workstation — Debian Slim + mise + AI agents
# Spec: docs/IMPLEMENTATION_PLAN.md
#
# Orca binary is NOT baked into the image by default.
# It installs into the persistent HOME volume on first boot and is upgraded via:
#   /scripts/update-orca.sh   or   mise run orca:update
# without rebuilding this image.
# Optional: ORCA_SEED_IN_IMAGE=true to bake a seed copy under /opt/orca-seed.

ARG DEBIAN_CODENAME=trixie
FROM debian:${DEBIAN_CODENAME}-slim

ARG PUID=1000
ARG PGID=1000
ARG ORCA_VERSION=latest
ARG ORCA_SHA256=
ARG ORCA_SEED_IN_IMAGE=false
ARG MISE_VERSION=
ARG NODE_VERSION=22
ARG PYTHON_VERSION=3.13
ARG UV_VERSION=latest

ARG INSTALL_CLAUDE=true
ARG INSTALL_CODEX=true
ARG INSTALL_GEMINI=true
ARG INSTALL_CURSOR=true
ARG INSTALL_OPENCODE=true
ARG INSTALL_GROK=true
ARG INSTALL_HERMES=true
ARG INSTALL_QWEN=true
ARG INSTALL_KIMI=true

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/orca \
    USER=orca \
    LANG=C.UTF-8 \
    ORCA_PORT=6768 \
    ORCA_VERSION=${ORCA_VERSION} \
    ORCA_INSTALL_DIR=/home/orca/.local/share/orca \
    LIBGL_ALWAYS_SOFTWARE=1 \
    PATH="/home/orca/.local/bin:/home/orca/.local/share/mise/shims:/usr/local/bin:${PATH}"

# --- Phase A: base + Electron libs (official headless matrix, Debian 13 t64 names) ---
# https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md
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
      libgtk-3-0t64 \
      libnss3 \
      libatk1.0-0t64 \
      libatk-bridge2.0-0t64 \
      libgbm1 \
      libasound2t64 \
      libxtst6 \
      libcups2t64 \
      libdrm2 \
      libxkbcommon0 \
      libpango-1.0-0 \
      libcairo2 \
      libatspi2.0-0t64 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxrandr2 \
      libxrender1 \
      libx11-xcb1 \
      libxcb-dri3-0 \
      libxss1 \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf "$(command -v fdfind)" /usr/local/bin/fd || true

# --- non-root user ---
RUN groupadd -g "${PGID}" orca \
 && useradd -m -u "${PUID}" -g "${PGID}" -s /bin/bash -d /home/orca orca \
 && mkdir -p /workspace /opt/orca-seed /scripts /opt/orca-server \
 && chown -R orca:orca /home/orca /workspace /opt/orca-seed

# --- GitHub CLI (official apt source) ---
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# supercronic — in-container schedule for mup (no host cron/systemd)
ARG SUPERCRONIC_VERSION=0.2.33
COPY scripts/install-supercronic.sh /tmp/install-supercronic.sh
RUN chmod +x /tmp/install-supercronic.sh \
 && SUPERCRONIC_VERSION="${SUPERCRONIC_VERSION}" /tmp/install-supercronic.sh \
 && rm -f /tmp/install-supercronic.sh

COPY scripts/ /scripts/
COPY config/mise.toml /opt/orca-server/mise.toml
COPY config/mup.crontab /opt/orca-server/mup.crontab
RUN chmod +x /scripts/*.sh \
 && cp /scripts/orca-wrapper.sh /usr/local/bin/orca \
 && chmod 755 /usr/local/bin/orca \
 && ln -sf /scripts/mup.sh /usr/local/bin/mup \
 && ln -sf /scripts/update-orca.sh /usr/local/bin/update-orca \
 && ln -sf /scripts/update-agents.sh /usr/local/bin/update-agents \
 && ln -sf /scripts/supervise.sh /usr/local/bin/supervise-orca

# --- Phase B: mise (as orca) ---
USER orca
WORKDIR /home/orca

RUN /scripts/install-mise.sh \
 && /scripts/bootstrap-runtimes.sh

# --- Optional seed of Orca into the image (still copied to volume on first boot) ---
USER root
RUN if [ "${ORCA_SEED_IN_IMAGE}" = "true" ]; then \
      ORCA_INSTALL_DIR=/opt/orca-seed HOME=/home/orca \
        /scripts/update-orca.sh "${ORCA_VERSION}" --force \
      && chown -R orca:orca /opt/orca-seed ; \
    else \
      echo "Skipping Orca seed in image (runtime install via volume)" ; \
    fi

# --- Phase E: agents (modular flags) — can also be refreshed at runtime via mise ---
USER orca
ENV INSTALL_CLAUDE=${INSTALL_CLAUDE} \
    INSTALL_CODEX=${INSTALL_CODEX} \
    INSTALL_GEMINI=${INSTALL_GEMINI} \
    INSTALL_CURSOR=${INSTALL_CURSOR} \
    INSTALL_OPENCODE=${INSTALL_OPENCODE} \
    INSTALL_GROK=${INSTALL_GROK} \
    INSTALL_HERMES=${INSTALL_HERMES} \
    INSTALL_QWEN=${INSTALL_QWEN} \
    INSTALL_KIMI=${INSTALL_KIMI}

RUN /scripts/install-agents.sh || echo "WARN: some agents failed during image build (can install later)"

USER orca
WORKDIR /workspace

# Port is for documentation only — compose uses Tailscale net namespace, no host publish
EXPOSE 6768

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
  CMD nc -z 127.0.0.1 ${ORCA_PORT:-6768} || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["serve"]
