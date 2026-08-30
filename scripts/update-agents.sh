#!/usr/bin/env bash
# update-agents.sh — install/upgrade AI CLIs into persistent HOME (no image rebuild)
# Called by mup / mise run agents:update
#
# Continues across optional agent failures. Primary npm agents honor INSTALL_* flags.
# npm packages install with prefix ~/.local so they survive container rebuilds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:${PATH}"
export npm_config_prefix="${HOME}/.local"

STATE_DIR="${HOME}/.local/state/orca-agent-manager"
mkdir -p "${STATE_DIR}/history" "${HOME}/.local/bin"

log()  { printf '[agents] %s\n' "$*"; }
warn() { printf '[agents] WARN: %s\n' "$*" >&2; }

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

record() {
  local agent="$1" old="$2" new="$3" result="$4"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${agent}" "${old}" "${new}" "${result}" \
    >>"${STATE_DIR}/history/agents.tsv"
}

bin_ver() {
  local bin="$1"
  if command -v "${bin}" >/dev/null 2>&1; then
    "${bin}" --version 2>/dev/null | head -1 || echo present
  else
    echo ""
  fi
}

need_npm() {
  command -v npm >/dev/null 2>&1
}

npm_install_or_update() {
  local label="$1" pkg="$2" bin="$3" version="${4:-}"
  local old new spec
  old="$(bin_ver "${bin}")"
  spec="${pkg}"
  if [[ -n "${version}" ]]; then
    spec="${pkg}@${version}"
  else
    spec="${pkg}@latest"
  fi
  log "Updating ${label}: npm install -g ${spec}"
  if npm install -g "${spec}"; then
    hash -r 2>/dev/null || true
    new="$(bin_ver "${bin}")"
    if [[ -n "${new}" ]]; then
      log "OK ${label}: ${old:-none} → ${new}"
      record "${label}" "${old:-none}" "${new}" "ok"
      return 0
    fi
    warn "${label}: install ok but ${bin} not on PATH"
    record "${label}" "${old:-none}" "missing-bin" "warn"
    return 1
  fi
  warn "${label}: npm install failed"
  record "${label}" "${old:-none}" "${old:-none}" "fail"
  return 1
}

update_claude() {
  truthy "${INSTALL_CLAUDE:-true}" || { log "SKIP Claude (disabled)"; return 0; }
  need_npm || { warn "npm missing"; return 1; }
  npm_install_or_update "claude" "@anthropic-ai/claude-code" "claude" "${CLAUDE_VERSION:-}"
}

update_codex() {
  truthy "${INSTALL_CODEX:-true}" || { log "SKIP Codex (disabled)"; return 0; }
  need_npm || { warn "npm missing"; return 1; }
  npm_install_or_update "codex" "@openai/codex" "codex" "${CODEX_VERSION:-}"
}

update_gemini() {
  truthy "${INSTALL_GEMINI:-true}" || { log "SKIP Gemini (disabled)"; return 0; }
  need_npm || { warn "npm missing"; return 1; }
  npm_install_or_update "gemini" "@google/gemini-cli" "gemini" "${GEMINI_VERSION:-}"
}

update_cursor() {
  truthy "${INSTALL_CURSOR:-true}" || { log "SKIP Cursor (disabled)"; return 0; }
  if [[ -n "${CURSOR_INSTALL_URL:-}" ]]; then
    local old
    old="$(bin_ver cursor)$(bin_ver cursor-agent)"
    log "Updating Cursor via CURSOR_INSTALL_URL"
    if curl -fsSL "${CURSOR_INSTALL_URL}" | bash; then
      record "cursor" "${old:-none}" "$(bin_ver cursor || bin_ver cursor-agent || echo present)" "ok"
      return 0
    fi
    record "cursor" "${old:-none}" "${old:-none}" "fail"
    return 1
  fi
  log "SKIP Cursor (set CURSOR_INSTALL_URL for official installer)"
  return 0
}

update_opencode() {
  truthy "${INSTALL_OPENCODE:-true}" || { log "SKIP OpenCode (disabled)"; return 0; }
  if [[ -n "${OPENCODE_INSTALL_URL:-}" ]]; then
    log "Updating OpenCode via OPENCODE_INSTALL_URL"
    curl -fsSL "${OPENCODE_INSTALL_URL}" | bash || return 1
    record "opencode" "?" "$(bin_ver opencode)" "ok"
    return 0
  fi
  if need_npm && npm view opencode >/dev/null 2>&1; then
    npm_install_or_update "opencode" "opencode" "opencode" "${OPENCODE_VERSION:-}" || true
    return 0
  fi
  log "SKIP OpenCode (no official method configured)"
  return 0
}

update_grok() {
  truthy "${INSTALL_GROK:-false}" || { log "SKIP Grok (disabled)"; return 0; }
  warn "Grok: no official install wired yet"
  return 0
}

update_hermes() {
  truthy "${INSTALL_HERMES:-false}" || { log "SKIP Hermes (disabled)"; return 0; }
  warn "Hermes: no official install wired yet"
  return 0
}

update_qwen() {
  truthy "${INSTALL_QWEN:-false}" || { log "SKIP Qwen (disabled)"; return 0; }
  warn "Qwen: no official install wired yet"
  return 0
}

update_kimi() {
  truthy "${INSTALL_KIMI:-false}" || { log "SKIP Kimi (disabled)"; return 0; }
  warn "Kimi: no official install wired yet"
  return 0
}

main() {
  local hard_fail=0
  # Primary agents: failures count
  update_claude || hard_fail=1
  update_codex || hard_fail=1
  update_gemini || hard_fail=1
  # Optional / best-effort
  update_cursor || true
  update_opencode || true
  update_grok || true
  update_hermes || true
  update_qwen || true
  update_kimi || true

  log "Agent pass complete (hard_fail=${hard_fail})"
  return "${hard_fail}"
}

main "$@"
