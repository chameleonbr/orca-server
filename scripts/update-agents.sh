#!/usr/bin/env bash
# update-agents.sh — install/upgrade AI CLIs into persistent HOME (no image rebuild)
# Called by mup / mise run agents:update
#
# Continues across optional agent failures. Primary npm agents honor INSTALL_* flags.
# npm packages install with prefix ~/.local so they survive container rebuilds.
set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [[ -L "${_src}" ]]; do
  _dir="$(cd "$(dirname "${_src}")" && pwd)"
  _src="$(readlink "${_src}")"
  [[ "${_src}" != /* ]] && _src="${_dir}/${_src}"
done
SCRIPT_DIR="$(cd "$(dirname "${_src}")" && pwd)"
[[ -x "${SCRIPT_DIR}/update-agents.sh" ]] || SCRIPT_DIR="/scripts"

export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:/scripts:${PATH}"
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
  # Official Cursor Agent installer (bins: agent, cursor-agent)
  # https://cursor.com/install → downloads.cursor.com lab package
  local url="${CURSOR_INSTALL_URL:-https://cursor.com/install}"
  local old
  old="$(bin_ver cursor-agent)$(bin_ver agent)$(bin_ver cursor)"
  log "Updating Cursor Agent via ${url}"
  if curl -fsSL "${url}" | bash; then
    hash -r 2>/dev/null || true
    # Prefer cursor-agent; also expose as cursor if missing
    if command -v cursor-agent >/dev/null 2>&1 && [[ ! -e "${HOME}/.local/bin/cursor" ]]; then
      ln -sf "$(command -v cursor-agent)" "${HOME}/.local/bin/cursor"
    fi
    local new
    new="$(bin_ver cursor-agent || bin_ver agent || bin_ver cursor || echo present)"
    log "OK cursor: ${old:-none} → ${new}"
    record "cursor" "${old:-none}" "${new}" "ok"
    return 0
  fi
  warn "Cursor installer failed"
  record "cursor" "${old:-none}" "${old:-none}" "fail"
  return 1
}

update_opencode() {
  truthy "${INSTALL_OPENCODE:-true}" || { log "SKIP OpenCode (disabled)"; return 0; }
  # Official: https://opencode.ai/docs — installer or npm package opencode-ai
  local url="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
  if [[ -n "${url}" ]]; then
    local old
    old="$(bin_ver opencode)"
    log "Updating OpenCode via ${url}"
    if curl -fsSL "${url}" | bash; then
      hash -r 2>/dev/null || true
      if [[ -x "${HOME}/.opencode/bin/opencode" ]] && [[ ! -e "${HOME}/.local/bin/opencode" ]]; then
        ln -sf "${HOME}/.opencode/bin/opencode" "${HOME}/.local/bin/opencode"
      fi
      record "opencode" "${old:-none}" "$(bin_ver opencode || echo present)" "ok"
      return 0
    fi
    warn "OpenCode installer failed — trying npm opencode-ai"
  fi
  if need_npm; then
    npm_install_or_update "opencode" "opencode-ai" "opencode" "${OPENCODE_VERSION:-}" || true
    return 0
  fi
  log "SKIP OpenCode (no method worked)"
  return 0
}

# --- Phase G optional agents (official packages confirmed) ---

update_grok() {
  # Official npm: @xai-official/grok → bin `grok`
  truthy "${INSTALL_GROK:-false}" || { log "SKIP Grok (disabled)"; return 0; }
  need_npm || { warn "npm missing"; return 1; }
  npm_install_or_update "grok" "@xai-official/grok" "grok" "${GROK_VERSION:-}"
}

update_hermes() {
  # Official PyPI: hermes-agent (Nous Research) → bin `hermes`
  # Prefer uv tool install into user path; fallback pip --user
  truthy "${INSTALL_HERMES:-false}" || { log "SKIP Hermes (disabled)"; return 0; }
  local old new
  old="$(bin_ver hermes)"
  log "Updating Hermes (hermes-agent via uv/pip)"
  if command -v uv >/dev/null 2>&1; then
    if uv tool install --force hermes-agent ${HERMES_VERSION:+=="${HERMES_VERSION}"} 2>/dev/null \
      || uv pip install --system hermes-agent ${HERMES_VERSION:+=="${HERMES_VERSION}"} 2>/dev/null \
      || uv pip install --python "$(command -v python3)" hermes-agent ${HERMES_VERSION:+=="${HERMES_VERSION}"}; then
      # uv tool often installs to ~/.local/bin
      hash -r 2>/dev/null || true
      if ! command -v hermes >/dev/null 2>&1; then
        # try common uv tool path
        if [[ -x "${HOME}/.local/bin/hermes" ]]; then
          :
        elif [[ -x "${HOME}/.local/share/uv/tools/hermes-agent/bin/hermes" ]]; then
          ln -sf "${HOME}/.local/share/uv/tools/hermes-agent/bin/hermes" "${HOME}/.local/bin/hermes"
        fi
      fi
      new="$(bin_ver hermes || echo present)"
      log "OK hermes: ${old:-none} → ${new}"
      record "hermes" "${old:-none}" "${new}" "ok"
      return 0
    fi
  fi
  if command -v pip3 >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    if python3 -m pip install --user ${HERMES_VERSION:+hermes-agent=="${HERMES_VERSION}"} ${HERMES_VERSION:-hermes-agent}; then
      hash -r 2>/dev/null || true
      new="$(bin_ver hermes || echo present)"
      log "OK hermes (pip): ${old:-none} → ${new}"
      record "hermes" "${old:-none}" "${new}" "ok"
      return 0
    fi
  fi
  warn "Hermes: install failed"
  record "hermes" "${old:-none}" "${old:-none}" "fail"
  return 1
}

update_qwen() {
  # Official npm: @qwen-code/qwen-code → bin `qwen`
  truthy "${INSTALL_QWEN:-false}" || { log "SKIP Qwen (disabled)"; return 0; }
  need_npm || { warn "npm missing"; return 1; }
  npm_install_or_update "qwen" "@qwen-code/qwen-code" "qwen" "${QWEN_VERSION:-}"
}

update_kimi() {
  # Official npm: @moonshot-ai/kimi-code → bin `kimi`
  truthy "${INSTALL_KIMI:-false}" || { log "SKIP Kimi (disabled)"; return 0; }
  need_npm || { warn "npm missing"; return 1; }
  npm_install_or_update "kimi" "@moonshot-ai/kimi-code" "kimi" "${KIMI_VERSION:-}"
}

main() {
  local hard_fail=0
  # Primary agents: failures count
  update_claude || hard_fail=1
  update_codex || hard_fail=1
  update_gemini || hard_fail=1
  # Optional / best-effort (Phase G + Cursor)
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
