#!/usr/bin/env bash
# install-mise.sh — official mise install for Linux, PATH for non-interactive shells
set -euo pipefail

log() { printf '[install-mise] %s\n' "$*"; }

export HOME="${HOME:-/home/orca}"
MISE_VERSION="${MISE_VERSION:-}"

mkdir -p "${HOME}/.local/bin"

if [[ -n "${MISE_VERSION}" ]]; then
  log "Installing mise ${MISE_VERSION}"
  curl -fsSL "https://mise.jdx.dev/install.sh" | MISE_VERSION="${MISE_VERSION}" sh
else
  log "Installing mise (latest)"
  curl -fsSL https://mise.jdx.dev/install.sh | sh
fi

# Ensure shim path for Docker non-login shells
MISE_BIN="${HOME}/.local/bin/mise"
if [[ ! -x "${MISE_BIN}" ]]; then
  # install.sh may place binary under ~/.local/bin
  if command -v mise >/dev/null 2>&1; then
    MISE_BIN="$(command -v mise)"
  else
    log "ERROR: mise binary not found after install"
    exit 1
  fi
fi

# Activate for subsequent RUN layers and runtime
{
  echo ''
  echo '# mise'
  echo "export PATH=\"${HOME}/.local/bin:${HOME}/.local/share/mise/shims:\$PATH\""
  echo "eval \"\$(${MISE_BIN} activate bash --shims)\""
} >> "${HOME}/.bashrc"

# Non-interactive profile
mkdir -p "${HOME}/.config/mise"
if [[ -f /opt/orca-server/mise.toml ]] && [[ ! -f "${HOME}/.config/mise/config.toml" ]]; then
  cp /opt/orca-server/mise.toml "${HOME}/.config/mise/config.toml"
fi

# System-wide PATH snippet for all shells in container
if [[ -w /etc/profile.d ]]; then
  cat > /tmp/mise-path.sh << EOF
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:\$PATH"
EOF
  # May need root — caller handles USER
  if [[ "$(id -u)" -eq 0 ]]; then
    cp /tmp/mise-path.sh /etc/profile.d/mise-path.sh
  fi
fi

export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}"
"${MISE_BIN}" --version
log "mise OK"
