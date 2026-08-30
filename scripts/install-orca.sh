#!/usr/bin/env bash
# install-orca.sh — download pinned Orca AppImage, extract without FUSE, install wrapper
# Runs as root during image build. See docs/IMPLEMENTATION_PLAN.md §5–6, §22.
set -euo pipefail

ORCA_VERSION="${ORCA_VERSION:-1.4.185}"
ORCA_SHA256="${ORCA_SHA256:-}"
ORCA_DIR="/opt/orca"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log() { printf '[install-orca] %s\n' "$*"; }

mkdir -p "${ORCA_DIR}"

# Official download URL must be confirmed against current Orca docs at build time.
# Placeholder pattern — verify against:
#   https://www.onorca.dev/docs/install
#   https://github.com/stablyai/orca
#   https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md
ORCA_URL="${ORCA_DOWNLOAD_URL:-}"

if [[ -z "${ORCA_URL}" ]]; then
  # Common AppImage naming; override with ORCA_DOWNLOAD_URL if upstream differs.
  ORCA_URL="https://github.com/stablyai/orca/releases/download/v${ORCA_VERSION}/orca-linux.AppImage"
fi

log "Downloading Orca ${ORCA_VERSION}"
log "URL: ${ORCA_URL}"

if ! curl -fL --retry 3 --retry-delay 2 -o "${TMP_DIR}/orca.AppImage" "${ORCA_URL}"; then
  log "ERROR: download failed. Set ORCA_DOWNLOAD_URL to the official asset for v${ORCA_VERSION}."
  log "Build cannot continue without a verified Orca binary (no fake install)."
  exit 1
fi

if [[ -n "${ORCA_SHA256}" ]]; then
  echo "${ORCA_SHA256}  ${TMP_DIR}/orca.AppImage" | sha256sum -c -
fi

chmod +x "${TMP_DIR}/orca.AppImage"

log "Extracting AppImage (no FUSE)"
cd "${TMP_DIR}"
./orca.AppImage --appimage-extract

rm -rf "${ORCA_DIR}/squashfs-root"
mv "${TMP_DIR}/squashfs-root" "${ORCA_DIR}/squashfs-root"
echo "${ORCA_VERSION}" > "${ORCA_DIR}/VERSION"

# Wrapper so `orca serve`, `orca account …` work
cat > /usr/local/bin/orca << 'EOF'
#!/bin/sh
exec /opt/orca/squashfs-root/AppRun "$@"
EOF
chmod 755 /usr/local/bin/orca

log "Installed Orca ${ORCA_VERSION} → ${ORCA_DIR}"
log "Wrapper: /usr/local/bin/orca"
