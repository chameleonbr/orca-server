#!/usr/bin/env bash
# install-supercronic.sh — container-native cron (no host systemd)
# https://github.com/aptible/supercronic
set -euo pipefail

VERSION="${SUPERCRONIC_VERSION:-0.2.33}"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ASSET="supercronic-linux-amd64" ;;
  aarch64|arm64) ASSET="supercronic-linux-arm64" ;;
  *) echo "unsupported arch: ${ARCH}"; exit 1 ;;
esac

URL="https://github.com/aptible/supercronic/releases/download/v${VERSION}/${ASSET}"
tmp="$(mktemp)"
echo "[supercronic] downloading ${URL}"
curl -fsSL "${URL}" -o "${tmp}"
chmod 755 "${tmp}"
mv "${tmp}" /usr/local/bin/supercronic
supercronic -version
