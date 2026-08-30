#!/usr/bin/env bash
# bootstrap-runtimes.sh — install Node/Python/uv via mise
set -euo pipefail

log() { printf '[bootstrap-runtimes] %s\n' "$*"; }

export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}"

NODE_VERSION="${NODE_VERSION:-22}"
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
UV_VERSION="${UV_VERSION:-latest}"

if ! command -v mise >/dev/null 2>&1; then
  log "ERROR: mise not found"
  exit 1
fi

# Seed config
mkdir -p "${HOME}/.config/mise"
if [[ -f /opt/orca-server/mise.toml ]] && [[ ! -f "${HOME}/.config/mise/config.toml" ]]; then
  cp /opt/orca-server/mise.toml "${HOME}/.config/mise/config.toml"
fi

log "Installing node@${NODE_VERSION}"
mise use -g "node@${NODE_VERSION}"

log "Installing python@${PYTHON_VERSION}"
mise use -g "python@${PYTHON_VERSION}"

log "Installing uv@${UV_VERSION}"
mise use -g "uv@${UV_VERSION}"

# Trust / reshim
mise reshim || true

log "node: $(node --version 2>/dev/null || echo missing)"
log "npm:  $(npm --version 2>/dev/null || echo missing)"
log "python: $(python3 --version 2>/dev/null || echo missing)"
log "uv: $(uv --version 2>/dev/null || echo missing)"
log "done"
