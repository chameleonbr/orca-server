#!/usr/bin/env bash
# entrypoint.sh — prepare volumes, ensure Orca runtime, start headless server
# All scheduling lives IN the container (supercronic) — nothing on the host.
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

ORCA_PORT="${ORCA_PORT:-6768}"
HOME="${HOME:-/home/orca}"
export HOME
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export ORCA_INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/share/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:/scripts:${PATH}"

# 1. Persistent dirs
mkdir -p "${HOME}" /workspace \
  "${HOME}/.local/bin" \
  "${HOME}/.local/share/mise" \
  "${HOME}/.local/share/orca" \
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

# 4. Ensure Orca runtime in persistent volume
# shellcheck source=/dev/null
source /scripts/lib-orca.sh

ensure_orca() {
  if orca_is_installed; then
    log "Orca present: $(orca_installed_version 2>/dev/null || echo unknown) @ ${ORCA_INSTALL_DIR}"
  else
    if [[ -x /opt/orca-seed/squashfs-root/AppRun ]]; then
      log "Seeding Orca from image /opt/orca-seed → ${ORCA_INSTALL_DIR}"
      mkdir -p "${ORCA_INSTALL_DIR}"
      cp -a /opt/orca-seed/squashfs-root "${ORCA_INSTALL_DIR}/"
      [[ -f /opt/orca-seed/VERSION ]] && cp -a /opt/orca-seed/VERSION "${ORCA_INSTALL_DIR}/VERSION"
      [[ -f /opt/orca-seed/orca-linux.AppImage ]] && cp -a /opt/orca-seed/orca-linux.AppImage "${ORCA_INSTALL_DIR}/" || true
      chmod -R a+rX "${ORCA_INSTALL_DIR}/squashfs-root"
    else
      log "Orca not installed — downloading into volume (no image rebuild needed later)"
      /scripts/update-orca.sh "${ORCA_VERSION:-latest}"
    fi
  fi

  # Refresh user-local wrapper
  mkdir -p "${HOME}/.local/bin"
  cat > "${HOME}/.local/bin/orca" << EOF
#!/bin/sh
export LIBGL_ALWAYS_SOFTWARE="\${LIBGL_ALWAYS_SOFTWARE:-1}"
exec "${ORCA_INSTALL_DIR}/squashfs-root/AppRun" "\$@"
EOF
  chmod 755 "${HOME}/.local/bin/orca"
}

# 5. Display: Orca starts its own Xvfb when DISPLAY is unset (official headless guide).
if [[ "${ORCA_USE_XVFB:-auto}" == "managed" ]]; then
  if ! pgrep -x Xvfb >/dev/null 2>&1; then
    log "Starting managed Xvfb on :99"
    Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
    export DISPLAY=:99
    sleep 0.5
  else
    export DISPLAY="${DISPLAY:-:99}"
  fi
fi

# 6. Pairing address (logged; supervise also reads env)
if [[ -n "${ORCA_PAIRING_ADDRESS:-}" ]]; then
  log "ORCA_PAIRING_ADDRESS=${ORCA_PAIRING_ADDRESS}"
elif [[ -n "${TAILSCALE_HOSTNAME:-}" ]]; then
  log "ORCA_PAIRING_ADDRESS unset — will advertise TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}"
else
  log "WARN: ORCA_PAIRING_ADDRESS not set. Prefer Tailscale IP/hostname for pairing."
fi

cmd="${1:-serve}"
shift || true

case "${cmd}" in
  serve)
    ensure_orca
    if ! orca_is_installed; then
      log "ERROR: Orca runtime missing after ensure_orca"
      exit 1
    fi
    # Supervisor: in-container mup schedule + orca child + recycle on binary upgrade
    # Nothing is installed on the Docker host.
    exec /scripts/supervise.sh
    ;;
  doctor)
    exec /scripts/doctor.sh "$@"
    ;;
  versions)
    exec /scripts/versions.sh "$@"
    ;;
  update-orca|orca:update)
    exec /scripts/update-orca.sh "$@"
    ;;
  update-agents|agents:update)
    exec /scripts/update-agents.sh "$@"
    ;;
  mup|update-all|update:all)
    exec /scripts/mup.sh "$@"
    ;;
  orca)
    ensure_orca
    exec orca "$@"
    ;;
  bash|sh)
    exec "${cmd}" "$@"
    ;;
  *)
    exec "${cmd}" "$@"
    ;;
esac
