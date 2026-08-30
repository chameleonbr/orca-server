#!/usr/bin/env bash
# install-agents.sh — modular AI CLI installers (official sources only)
# See docs/IMPLEMENTATION_PLAN.md §12–21, §68–70
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
  # Official installer must be confirmed at implementation time.
  # Do not guess npm package names.
  if [[ -n "${CURSOR_INSTALL_URL:-}" ]]; then
    log "Installing Cursor CLI from CURSOR_INSTALL_URL"
    curl -fsSL "${CURSOR_INSTALL_URL}" | bash
    verify_bin cursor || verify_bin cursor-agent || true
  else
    warn "Cursor CLI: set CURSOR_INSTALL_URL or implement official method — skipped (build continues)"
  fi
}

install_opencode() {
  truthy "${INSTALL_OPENCODE:-true}" || { log "SKIP OpenCode"; return 0; }
  if [[ -n "${OPENCODE_INSTALL_URL:-}" ]]; then
    log "Installing OpenCode from OPENCODE_INSTALL_URL"
    curl -fsSL "${OPENCODE_INSTALL_URL}" | bash
    verify_bin opencode || true
  else
    # Try common official npm name only if documented; otherwise skip cleanly
    if need_npm && npm view opencode >/dev/null 2>&1; then
      install_pkg_npm opencode "opencode" "${OPENCODE_VERSION:-}" || warn "OpenCode npm install failed"
      verify_bin opencode || true
    else
      warn "OpenCode: official install method not configured — skipped"
    fi
  fi
}

install_grok() {
  truthy "${INSTALL_GROK:-false}" || { log "SKIP Grok (disabled)"; return 0; }
  warn "Grok: install only after confirming Orca-expected CLI + official distribution — not implemented"
  return 0
}

install_hermes() {
  truthy "${INSTALL_HERMES:-false}" || { log "SKIP Hermes (disabled)"; return 0; }
  warn "Hermes: install only after confirming Orca-supported project + official binary — not implemented"
  return 0
}

install_qwen() {
  truthy "${INSTALL_QWEN:-false}" || { log "SKIP Qwen (disabled)"; return 0; }
  warn "Qwen Code: official distribution not configured — not implemented"
  return 0
}

install_kimi() {
  truthy "${INSTALL_KIMI:-false}" || { log "SKIP Kimi (disabled)"; return 0; }
  warn "Kimi: official distribution not configured — not implemented"
  return 0
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
    # Primary npm agents failing should fail the build
    exit 1
  fi
  log "Agent install pass complete"
}

main "$@"
