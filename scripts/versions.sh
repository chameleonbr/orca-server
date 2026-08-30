#!/usr/bin/env bash
# versions.sh — print installed runtime and agent versions
set -euo pipefail

export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:${PATH}"
export ORCA_INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/share/orca}"

ver() {
  local label="$1" bin="$2"
  if command -v "${bin}" >/dev/null 2>&1; then
    printf '%-12s %s\n' "${label}:" "$(${bin} --version 2>/dev/null | head -1 || echo present)"
  else
    printf '%-12s %s\n' "${label}:" "not installed"
  fi
}

echo "=== versions ==="
if [[ -f "${ORCA_INSTALL_DIR}/VERSION" ]]; then
  printf '%-12s %s\n' "Orca:" "$(cat "${ORCA_INSTALL_DIR}/VERSION")  (${ORCA_INSTALL_DIR})"
elif [[ -f /opt/orca-seed/VERSION ]]; then
  printf '%-12s %s\n' "Orca seed:" "$(cat /opt/orca-seed/VERSION)  (/opt/orca-seed)"
else
  printf '%-12s %s\n' "Orca:" "not installed — run /scripts/update-orca.sh"
fi
ver "mise" mise
ver "Node" node
ver "npm" npm
ver "Python" python3
ver "uv" uv
ver "git" git
ver "gh" gh
ver "Claude" claude
ver "Codex" codex
ver "Gemini" gemini
ver "Cursor" cursor
ver "OpenCode" opencode
