#!/usr/bin/env bash
# install-agents.sh — modular AI CLI installers (official sources only)
# See docs/IMPLEMENTATION_PLAN.md §12–21, §68–70
# Mirrors update-agents.sh methods for image build / first seed.
set -euo pipefail

log() { printf '[install-agents] %s\n' "$*"; }
warn() { printf '[install-agents] WARN: %s\n' "$*" >&2; }

export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:${PATH}"
export npm_config_prefix="${HOME}/.local"

mkdir -p "${HOME}/.local/bin"

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

need_npm() {
  if ! command -v npm >/dev/null 2>&1; then
    warn "npm not available — cannot install npm-based agents"
    return 1
  fi
  return 0
}

install_pkg_npm() {
  local name="$1" pkg="$2" version="${3:-}"
  local spec="${pkg}"
  if [[ -n "${version}" ]]; then
    spec="${pkg}@${version}"
  fi
  log "npm install -g ${spec}"
  npm install -g "${spec}"
}

verify_bin() {
  local bin="$1"
  if command -v "${bin}" >/dev/null 2>&1; then
    log "OK ${bin}: $(${bin} --version 2>/dev/null | head -1 || echo present)"
    return 0
  fi
  warn "${bin} not on PATH after install"
  return 1
}

install_claude() {
  truthy "${INSTALL_CLAUDE:-true}" || { log "SKIP Claude"; return 0; }
  need_npm || return 1
  install_pkg_npm claude "@anthropic-ai/claude-code" "${CLAUDE_VERSION:-}"
  verify_bin claude
}

install_codex() {
  truthy "${INSTALL_CODEX:-true}" || { log "SKIP Codex"; return 0; }
  need_npm || return 1
  install_pkg_npm codex "@openai/codex" "${CODEX_VERSION:-}"
  verify_bin codex
}

install_gemini() {
  truthy "${INSTALL_GEMINI:-true}" || { log "SKIP Gemini"; return 0; }
  need_npm || return 1
  install_pkg_npm gemini "@google/gemini-cli" "${GEMINI_VERSION:-}"
  verify_bin gemini
}

install_cursor() {
  truthy "${INSTALL_CURSOR:-true}" || { log "SKIP Cursor"; return 0; }
  local url="${CURSOR_INSTALL_URL:-https://cursor.com/install}"
  log "Installing Cursor Agent from ${url}"
  if curl -fsSL "${url}" | bash; then
    if command -v cursor-agent >/dev/null 2>&1 && [[ ! -e "${HOME}/.local/bin/cursor" ]]; then
      ln -sf "$(command -v cursor-agent)" "${HOME}/.local/bin/cursor"
    fi
    verify_bin cursor-agent || verify_bin agent || verify_bin cursor || true
  else
    warn "Cursor CLI install failed — skipped (build continues)"
  fi
}

install_opencode() {
  truthy "${INSTALL_OPENCODE:-true}" || { log "SKIP OpenCode"; return 0; }
  local url="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
  log "Installing OpenCode from ${url}"
  if curl -fsSL "${url}" | bash; then
    if [[ -x "${HOME}/.opencode/bin/opencode" ]]; then
      ln -sf "${HOME}/.opencode/bin/opencode" "${HOME}/.local/bin/opencode"
    fi
    verify_bin opencode || true
    return 0
  fi
  if need_npm; then
    install_pkg_npm opencode "opencode-ai" "${OPENCODE_VERSION:-}" || warn "OpenCode npm install failed"
    verify_bin opencode || true
  else
    warn "OpenCode: install failed"
  fi
}

install_grok() {
  truthy "${INSTALL_GROK:-false}" || { log "SKIP Grok (disabled)"; return 0; }
  need_npm || return 0
  install_pkg_npm grok "@xai-official/grok" "${GROK_VERSION:-}" || warn "Grok install failed"
  verify_bin grok || true
}

install_hermes() {
  truthy "${INSTALL_HERMES:-false}" || { log "SKIP Hermes (disabled)"; return 0; }
  log "Installing hermes-agent (PyPI)"
  if command -v uv >/dev/null 2>&1; then
    uv tool install --force hermes-agent ${HERMES_VERSION:+=="${HERMES_VERSION}"} \
      || uv pip install --python "$(command -v python3)" hermes-agent ${HERMES_VERSION:+=="${HERMES_VERSION}"} \
      || true
    if [[ -x "${HOME}/.local/share/uv/tools/hermes-agent/bin/hermes" ]]; then
      ln -sf "${HOME}/.local/share/uv/tools/hermes-agent/bin/hermes" "${HOME}/.local/bin/hermes"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user hermes-agent ${HERMES_VERSION:+=="${HERMES_VERSION}"} || true
  fi
  verify_bin hermes || true
}

install_qwen() {
  truthy "${INSTALL_QWEN:-false}" || { log "SKIP Qwen (disabled)"; return 0; }
  need_npm || return 0
  install_pkg_npm qwen "@qwen-code/qwen-code" "${QWEN_VERSION:-}" || warn "Qwen install failed"
  verify_bin qwen || true
}

install_kimi() {
  truthy "${INSTALL_KIMI:-false}" || { log "SKIP Kimi (disabled)"; return 0; }
  need_npm || return 0
  install_pkg_npm kimi "@moonshot-ai/kimi-code" "${KIMI_VERSION:-}" || warn "Kimi install failed"
  verify_bin kimi || true
}

main() {
  local failed=0
  install_claude || failed=1
  install_codex || failed=1
  install_gemini || failed=1
  install_cursor || true
  install_opencode || true
  install_grok || true
  install_hermes || true
  install_qwen || true
  install_kimi || true

  if [[ "${failed}" -ne 0 ]]; then
    warn "One or more primary agents failed to install"
    exit 1
  fi
  log "Agent install pass complete"
}

main "$@"
