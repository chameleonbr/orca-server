#!/usr/bin/env bash
# entrypoint.sh — prepare volumes and start Orca Server headless
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

ORCA_PORT="${ORCA_PORT:-6768}"
HOME="${HOME:-/home/orca}"
export HOME

# 1. Persistent dirs
mkdir -p "${HOME}" /workspace \
  "${HOME}/.local/bin" \
  "${HOME}/.local/share/mise" \
  "${HOME}/.config/mise" \
  "${HOME}/.cache/mise" \
  "${HOME}/.ssh" \
  "${HOME}/.local/state/orca-agent-manager"

# 2. Seed mise config if missing (never overwrite custom)
if [[ ! -f "${HOME}/.config/mise/config.toml" ]] && [[ -f /opt/orca-server/mise.toml ]]; then
  mkdir -p "${HOME}/.config/mise"
  cp /opt/orca-server/mise.toml "${HOME}/.config/mise/config.toml"
  log "Seeded mise config from /opt/orca-server/mise.toml"
fi

# 3. SSH perms when keys present
if [[ -d "${HOME}/.ssh" ]]; then
  chmod 700 "${HOME}/.ssh" || true
  find "${HOME}/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
fi

# 4. Optional agent auto-update (must not block Orca on optional failure)
if [[ "${AUTO_UPDATE_AGENTS:-false}" == "true" ]]; then
  log "AUTO_UPDATE_AGENTS=true — running mise run agents:update"
  if command -v mise >/dev/null 2>&1; then
    mise run agents:update || log "WARN: agents:update failed (non-fatal)"
  else
    log "WARN: mise not found; skipping agents:update"
  fi
fi

# 5. Xvfb if needed (Electron-derived runtime)
if [[ "${ORCA_USE_XVFB:-true}" == "true" ]]; then
  if ! pgrep -x Xvfb >/dev/null 2>&1; then
    log "Starting Xvfb on :99"
    Xvfb :99 -screen 0 1280x720x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
    export DISPLAY=:99
    sleep 0.5
  else
    export DISPLAY="${DISPLAY:-:99}"
  fi
fi

# 6. Pairing address
PAIRING_ARGS=()
if [[ -n "${ORCA_PAIRING_ADDRESS:-}" ]]; then
  PAIRING_ARGS+=(--pairing-address "${ORCA_PAIRING_ADDRESS}")
  log "ORCA_PAIRING_ADDRESS=${ORCA_PAIRING_ADDRESS}"
else
  # Prefer MagicDNS hostname when available
  if [[ -n "${TAILSCALE_HOSTNAME:-}" ]]; then
    log "ORCA_PAIRING_ADDRESS unset — using TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}"
    PAIRING_ARGS+=(--pairing-address "${TAILSCALE_HOSTNAME}")
  else
    log "WARN: ORCA_PAIRING_ADDRESS not set. Set it to the Tailscale IP/hostname for reliable pairing."
  fi
fi

# 7. Ensure orca wrapper exists
if ! command -v orca >/dev/null 2>&1; then
  log "ERROR: 'orca' not on PATH. Did install-orca.sh run during image build?"
  exit 1
fi

cmd="${1:-serve}"
shift || true

if [[ "${cmd}" == "serve" ]]; then
  log "Starting: orca serve --port ${ORCA_PORT} ${PAIRING_ARGS[*]:-}"
  # shellcheck disable=SC2086
  exec orca serve --port "${ORCA_PORT}" ${PAIRING_ARGS[@]+"${PAIRING_ARGS[@]}"} "$@"
fi

if [[ "${cmd}" == "doctor" ]]; then
  exec /scripts/doctor.sh "$@"
fi

if [[ "${cmd}" == "versions" ]]; then
  exec /scripts/versions.sh "$@"
fi

# Pass-through: orca <args> or arbitrary command
if [[ "${cmd}" == "orca" ]]; then
  exec orca "$@"
fi

exec "${cmd}" "$@"
