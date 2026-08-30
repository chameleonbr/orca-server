#!/usr/bin/env bash
# install-orca.sh — DEPRECATED as build-time bake.
# Orca is installed into the persistent volume via update-orca.sh.
# Kept as a thin alias so older docs/calls keep working.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/update-orca.sh" "$@"
