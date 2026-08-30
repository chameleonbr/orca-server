#!/usr/bin/env bash
# mup.sh — Mise UPdate-all: runtimes + Orca + AI agents in one command
# Intended entrypoints:
#   mise run mup
#   mup
#   /scripts/mup.sh
#
# Env:
#   MUP_ORCA=true|false       (default true)
#   MUP_AGENTS=true|false     (default true)
#   MUP_TOOLS=true|false      (default true)  # mise install/upgrade node/python/uv
#   MUP_RESTART_HINT=true     (default true)
#   ORCA_VERSION=latest|vX.Y.Z
#   INSTALL_*=true|false      agent flags
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:/scripts:${PATH}"
export ORCA_INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/share/orca}"
export npm_config_prefix="${HOME}/.local"

STATE_DIR="${HOME}/.local/state/orca-agent-manager"
mkdir -p "${STATE_DIR}"
LOG_FILE="${STATE_DIR}/mup-$(date -u +%Y%m%dT%H%M%SZ).log"
SUMMARY="${STATE_DIR}/mup-last-summary.txt"

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON|"") return 0 ;; # empty = default on for component flags below
    *) return 1 ;;
  esac
}

# Component flags: empty defaults to true
flag_on() {
  local v="${1:-true}"
  case "${v}" in
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) return 0 ;;
  esac
}

log() {
  local line
  line="$(printf '[mup] %s\n' "$*")"
  printf '%s' "${line}"
  printf '%s' "${line}" >>"${LOG_FILE}"
}

ok()   { log "OK   $*"; }
skip() { log "SKIP $*"; }
fail() { log "FAIL $*"; }

STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ORCA_BEFORE=""
ORCA_AFTER=""
ORCA_CHANGED=0
FAILURES=0

log "=== mup start ${STARTED_AT} ==="
log "log=${LOG_FILE}"
log "HOME=${HOME}"

# --- 1. mise tool upgrades ---
if flag_on "${MUP_TOOLS:-true}"; then
  log "--- tools (mise) ---"
  if command -v mise >/dev/null 2>&1; then
    # Ensure base config exists
    if [[ ! -f "${HOME}/.config/mise/config.toml" ]] && [[ -f /opt/orca-server/mise.toml ]]; then
      mkdir -p "${HOME}/.config/mise"
      cp /opt/orca-server/mise.toml "${HOME}/.config/mise/config.toml"
    fi
    if mise install 2>>"${LOG_FILE}"; then
      ok "mise install"
    else
      fail "mise install"
      FAILURES=$((FAILURES + 1))
    fi
    # upgrade plugins/tools when supported
    if mise upgrade 2>>"${LOG_FILE}"; then
      ok "mise upgrade"
    else
      # older mise may not have upgrade — non-fatal
      skip "mise upgrade (not available or no-op)"
    fi
    {
      echo "node: $(node --version 2>/dev/null || echo n/a)"
      echo "npm: $(npm --version 2>/dev/null || echo n/a)"
      echo "python: $(python3 --version 2>/dev/null || echo n/a)"
      echo "uv: $(uv --version 2>/dev/null || echo n/a)"
      echo "mise: $(mise --version 2>/dev/null || echo n/a)"
    } | while read -r l; do log "  ${l}"; done
  else
    fail "mise not found"
    FAILURES=$((FAILURES + 1))
  fi
else
  skip "tools (MUP_TOOLS=false)"
fi

# --- 2. Orca ---
if flag_on "${MUP_ORCA:-true}"; then
  log "--- orca ---"
  if [[ -x "${SCRIPT_DIR}/update-orca.sh" ]]; then
    ORCA_BEFORE="$("${SCRIPT_DIR}/update-orca.sh" --status 2>/dev/null | awk -F= '/^version=/{print $2; exit}' || true)"
    if "${SCRIPT_DIR}/update-orca.sh" "${ORCA_VERSION:-latest}" >>"${LOG_FILE}" 2>&1; then
      ORCA_AFTER="$("${SCRIPT_DIR}/update-orca.sh" --status 2>/dev/null | awk -F= '/^version=/{print $2; exit}' || true)"
      if [[ -n "${ORCA_BEFORE}" && -n "${ORCA_AFTER}" && "${ORCA_BEFORE}" != "${ORCA_AFTER}" ]]; then
        ok "Orca ${ORCA_BEFORE} → ${ORCA_AFTER}"
        ORCA_CHANGED=1
      else
        ok "Orca ${ORCA_AFTER:-${ORCA_BEFORE:-unknown}} (unchanged or fresh install)"
      fi
    else
      fail "Orca update"
      FAILURES=$((FAILURES + 1))
    fi
  else
    fail "update-orca.sh missing"
    FAILURES=$((FAILURES + 1))
  fi
else
  skip "orca (MUP_ORCA=false)"
fi

# --- 3. Agents ---
if flag_on "${MUP_AGENTS:-true}"; then
  log "--- agents ---"
  if [[ -x "${SCRIPT_DIR}/update-agents.sh" ]]; then
    if "${SCRIPT_DIR}/update-agents.sh" >>"${LOG_FILE}" 2>&1; then
      ok "agents update finished"
    else
      fail "agents update (see log — optional agents may fail without blocking)"
      # update-agents returns non-zero only on primary hard failures
      FAILURES=$((FAILURES + 1))
    fi
  else
    fail "update-agents.sh missing"
    FAILURES=$((FAILURES + 1))
  fi
else
  skip "agents (MUP_AGENTS=false)"
fi

FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "started=${STARTED_AT}"
  echo "finished=${FINISHED_AT}"
  echo "failures=${FAILURES}"
  echo "orca_before=${ORCA_BEFORE}"
  echo "orca_after=${ORCA_AFTER}"
  echo "orca_changed=${ORCA_CHANGED}"
  echo "log=${LOG_FILE}"
} >"${SUMMARY}"

log "=== mup done failures=${FAILURES} orca_changed=${ORCA_CHANGED} ==="
log "summary=${SUMMARY}"

if flag_on "${MUP_RESTART_HINT:-true}" && [[ "${ORCA_CHANGED}" -eq 1 ]]; then
  log "HINT: Orca binary changed — supervisor will recycle orca (in-container)"
  log "  (or: docker compose restart orca)"
  # Signal file for in-container supervise.sh
  echo "1" >"${STATE_DIR}/orca-restart-needed"
fi

# Exit 0 if only soft issues? Prefer non-zero when failures > 0 so cron/systemd notice.
if [[ "${FAILURES}" -gt 0 ]]; then
  exit 1
fi
exit 0
