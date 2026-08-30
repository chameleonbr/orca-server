#!/bin/sh
# System wrapper — prefers persistent HOME install, falls back to image seed if present.
# Orca is updatable via /scripts/update-orca.sh without rebuilding the image.
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

HOME="${HOME:-/home/orca}"
ORCA_DIR="${ORCA_INSTALL_DIR:-$HOME/.local/share/orca}"
APPRUN="$ORCA_DIR/squashfs-root/AppRun"
SEED="/opt/orca-seed/squashfs-root/AppRun"

if [ -x "$APPRUN" ]; then
  exec "$APPRUN" "$@"
fi

if [ -x "$SEED" ]; then
  exec "$SEED" "$@"
fi

echo "orca: runtime not found." >&2
echo "  Expected: $APPRUN" >&2
echo "  Run: /scripts/update-orca.sh   (or: mise run orca:update)" >&2
exit 127
