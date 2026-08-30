#!/usr/bin/env bash
# update-orca.sh — install or upgrade Orca AppImage into the persistent HOME volume
# WITHOUT rebuilding the Docker image.
#
# Usage:
#   update-orca.sh                 # install/upgrade to ORCA_VERSION or latest
#   update-orca.sh 1.4.192         # pin a version
#   update-orca.sh latest
#   update-orca.sh --rollback      # restore previous extract
#   update-orca.sh --status
#
# Official: headless Orca never self-updates — replace binary + restart process.
#   https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-orca.sh
source "${SCRIPT_DIR}/lib-orca.sh"

export HOME="${HOME:-/home/orca}"
ORCA_DIR="$(orca_default_install_dir)"
export ORCA_INSTALL_DIR="${ORCA_DIR}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [version|latest] [--rollback] [--status] [--force]

Install/upgrade Orca into: ${ORCA_DIR}
State (pairing/projects) stays in ~/.config and is NOT touched.

After a successful upgrade, restart the container / orca process:
  docker compose restart orca
EOF
}

cmd_status() {
  echo "ORCA_INSTALL_DIR=${ORCA_DIR}"
  if orca_is_installed; then
    echo "installed=yes"
    echo "version=$(orca_installed_version 2>/dev/null || echo unknown)"
    echo "apprun=$(orca_apprun)"
    if [[ -d "${ORCA_DIR}/previous/squashfs-root" ]]; then
      echo "rollback_available=yes"
      echo "previous_version=$(cat "${ORCA_DIR}/previous/VERSION" 2>/dev/null || echo unknown)"
    else
      echo "rollback_available=no"
    fi
  else
    echo "installed=no"
  fi
}

cmd_rollback() {
  [[ -d "${ORCA_DIR}/previous/squashfs-root" ]] || orca_die "No previous install to roll back to"
  orca_log "Rolling back Orca → $(cat "${ORCA_DIR}/previous/VERSION" 2>/dev/null || echo unknown)"

  local staging="${ORCA_DIR}/.rollback-staging.$$"
  rm -rf "${staging}"
  mkdir -p "${staging}"

  # Move current aside, previous into place
  if [[ -d "${ORCA_DIR}/squashfs-root" ]]; then
    mv "${ORCA_DIR}/squashfs-root" "${staging}/squashfs-root"
    [[ -f "${ORCA_DIR}/VERSION" ]] && mv "${ORCA_DIR}/VERSION" "${staging}/VERSION"
    [[ -f "${ORCA_DIR}/orca-linux.AppImage" ]] && mv "${ORCA_DIR}/orca-linux.AppImage" "${staging}/orca-linux.AppImage" || true
  fi

  mv "${ORCA_DIR}/previous/squashfs-root" "${ORCA_DIR}/squashfs-root"
  [[ -f "${ORCA_DIR}/previous/VERSION" ]] && mv "${ORCA_DIR}/previous/VERSION" "${ORCA_DIR}/VERSION"
  [[ -f "${ORCA_DIR}/previous/orca-linux.AppImage" ]] && mv "${ORCA_DIR}/previous/orca-linux.AppImage" "${ORCA_DIR}/orca-linux.AppImage" || true
  rm -rf "${ORCA_DIR}/previous"
  mkdir -p "${ORCA_DIR}/previous"
  if [[ -d "${staging}/squashfs-root" ]]; then
    mv "${staging}/squashfs-root" "${ORCA_DIR}/previous/squashfs-root"
    [[ -f "${staging}/VERSION" ]] && mv "${staging}/VERSION" "${ORCA_DIR}/previous/VERSION"
    [[ -f "${staging}/orca-linux.AppImage" ]] && mv "${staging}/orca-linux.AppImage" "${ORCA_DIR}/previous/orca-linux.AppImage" || true
  fi
  rm -rf "${staging}"

  chmod -R a+rX "${ORCA_DIR}/squashfs-root"
  orca_log "Rollback complete: $(orca_installed_version)"
  orca_log "Restart the Orca process to use the rolled-back binary."
}

install_or_upgrade() {
  local version_arg="${1:-${ORCA_VERSION:-latest}}"
  local force="${2:-0}"
  local resolved_tag url tmp work

  orca_select_asset

  if [[ "$(orca_normalize_version "${version_arg}")" == "latest" ]]; then
    resolved_tag="$(orca_resolve_latest_tag)"
  else
    resolved_tag="$(orca_normalize_version "${version_arg}")"
  fi

  local current
  current="$(orca_installed_version 2>/dev/null || true)"
  if [[ "${force}" != "1" && -n "${current}" && "${current}" == "${resolved_tag}" ]] && orca_is_installed; then
    orca_log "Already on ${resolved_tag} — nothing to do (use --force to reinstall)"
    return 0
  fi

  url="$(orca_resolve_download_url "${resolved_tag}")"
  orca_log "Target: ${resolved_tag}"
  orca_log "Asset:  ${ORCA_ASSET}"
  orca_log "URL:    ${url}"
  orca_log "Dest:   ${ORCA_DIR}"

  mkdir -p "${ORCA_DIR}"
  tmp="$(mktemp -d "${ORCA_DIR}/.download.XXXXXX")"
  work="$(mktemp -d "${ORCA_DIR}/.extract.XXXXXX")"
  cleanup() {
    rm -rf "${tmp}" "${work}"
  }
  trap cleanup EXIT

  # Capacity hint (~2x AppImage for download + extract)
  if command -v df >/dev/null 2>&1; then
    orca_log "Disk free on install fs: $(df -h "${ORCA_DIR}" | awk 'NR==2{print $4}')"
  fi

  orca_log "Downloading…"
  curl -fL --retry 3 --retry-delay 2 -o "${tmp}/${ORCA_ASSET}" "${url}"

  if [[ -n "${ORCA_SHA256:-}" ]]; then
    echo "${ORCA_SHA256}  ${tmp}/${ORCA_ASSET}" | sha256sum -c -
  fi

  # Basic sanity: AppImage / ELF
  if command -v file >/dev/null 2>&1; then
    file "${tmp}/${ORCA_ASSET}" | grep -qiE 'ELF|executable' \
      || orca_die "Downloaded file does not look like an executable AppImage"
  fi

  chmod +x "${tmp}/${ORCA_ASSET}"

  orca_log "Extracting AppImage (no FUSE)…"
  (
    cd "${work}"
    # AppImage extract writes ./squashfs-root (file list is noisy — keep a log)
    if ! "${tmp}/${ORCA_ASSET}" --appimage-extract >"${ORCA_DIR}/.last-extract.log" 2>&1; then
      orca_die "AppImage extract failed — see ${ORCA_DIR}/.last-extract.log"
    fi
  )
  [[ -x "${work}/squashfs-root/AppRun" ]] || orca_die "Extract failed: AppRun missing"

  # AppImage extract is mode 0700 — fix so non-extracting contexts can traverse
  chmod -R a+rX "${work}/squashfs-root"

  # Preserve current as previous (for rollback)
  if orca_is_installed; then
    orca_log "Saving current install as previous ($(orca_installed_version 2>/dev/null || echo unknown))"
    rm -rf "${ORCA_DIR}/previous"
    mkdir -p "${ORCA_DIR}/previous"
    mv "${ORCA_DIR}/squashfs-root" "${ORCA_DIR}/previous/squashfs-root"
    [[ -f "${ORCA_DIR}/VERSION" ]] && cp -a "${ORCA_DIR}/VERSION" "${ORCA_DIR}/previous/VERSION"
    [[ -f "${ORCA_DIR}/orca-linux.AppImage" ]] && mv "${ORCA_DIR}/orca-linux.AppImage" "${ORCA_DIR}/previous/orca-linux.AppImage" || true
  fi

  # Atomic-ish switch: move new tree into place
  rm -rf "${ORCA_DIR}/squashfs-root"
  mv "${work}/squashfs-root" "${ORCA_DIR}/squashfs-root"
  mv "${tmp}/${ORCA_ASSET}" "${ORCA_DIR}/orca-linux.AppImage"
  printf '%s\n' "${resolved_tag}" > "${ORCA_DIR}/VERSION"
  chmod -R a+rX "${ORCA_DIR}/squashfs-root"

  # Keep only one previous generation
  # (already done)

  # Ensure PATH wrapper exists for interactive shells (image also ships one)
  mkdir -p "${HOME}/.local/bin"
  cat > "${HOME}/.local/bin/orca" << EOF
#!/bin/sh
# Persistent wrapper — always runs the volume-installed Orca
export LIBGL_ALWAYS_SOFTWARE="\${LIBGL_ALWAYS_SOFTWARE:-1}"
APPRUN="${ORCA_DIR}/squashfs-root/AppRun"
if [ ! -x "\$APPRUN" ]; then
  echo "orca: not installed at ${ORCA_DIR} — run update-orca.sh" >&2
  exit 127
fi
exec "\$APPRUN" "\$@"
EOF
  chmod 755 "${HOME}/.local/bin/orca"

  orca_log "Installed Orca ${resolved_tag} → ${ORCA_DIR}"
  orca_log "Restart the Orca process to load the new binary (docker compose restart orca)."
  trap - EXIT
  cleanup
}

# --- main ---
FORCE=0
ACTION="install"
VERSION_ARG="${ORCA_VERSION:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --status) ACTION="status"; shift ;;
    --rollback) ACTION="rollback"; shift ;;
    --force) FORCE=1; shift ;;
    latest) VERSION_ARG="latest"; shift ;;
    v[0-9]*|[0-9]*.[0-9]*) VERSION_ARG="$1"; shift ;;
    *)
      orca_die "Unknown argument: $1 (see --help)"
      ;;
  esac
done

case "${ACTION}" in
  status) cmd_status ;;
  rollback) cmd_rollback ;;
  install) install_or_upgrade "${VERSION_ARG}" "${FORCE}" ;;
esac
