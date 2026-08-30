#!/usr/bin/env bash
# doctor.sh — environment diagnostics (no secrets)
set -euo pipefail

export HOME="${HOME:-/home/orca}"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:/usr/local/bin:${PATH}"

ok()   { printf '[OK]   %s\n' "$*"; }
skip() { printf '[SKIP] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }

check_cmd() {
  local label="$1" bin="$2" required="${3:-0}"
  if command -v "${bin}" >/dev/null 2>&1; then
    local ver
    ver="$(${bin} --version 2>/dev/null | head -1 || echo present)"
    ok "${label}: ${ver}"
    return 0
  fi
  if [[ "${required}" == "1" ]]; then
    fail "${label} (${bin}) missing"
    return 1
  fi
  skip "${label} not installed"
  return 0
}

echo "=== orca-server doctor ==="
echo "HOME=${HOME}"
echo "WORKSPACE=/workspace"
echo "ORCA_PORT=${ORCA_PORT:-6768}"
echo "ORCA_PAIRING_ADDRESS=${ORCA_PAIRING_ADDRESS:-<unset>}"
echo "TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-<unset>}"
if [[ -f /opt/orca/VERSION ]]; then
  echo "ORCA_VERSION_FILE=$(cat /opt/orca/VERSION)"
fi
echo

rc=0
check_cmd "orca" orca 1 || rc=1
check_cmd "git" git 1 || rc=1
check_cmd "gh" gh 0 || true
check_cmd "mise" mise 1 || rc=1
check_cmd "node (mise)" node 1 || rc=1
check_cmd "npm" npm 1 || rc=1
check_cmd "python" python3 0 || true
check_cmd "uv" uv 0 || true
check_cmd "claude" claude 0 || true
check_cmd "codex" codex 0 || true
check_cmd "gemini" gemini 0 || true
check_cmd "cursor" cursor 0 || true
check_cmd "opencode" opencode 0 || true
check_cmd "rg" rg 0 || true
check_cmd "fd" fd 0 || true

echo
if command -v ss >/dev/null 2>&1; then
  echo "=== listening ports (ss -lntp) ==="
  ss -lntp 2>/dev/null || true
fi

# Tailscale: CLI may live only in sidecar; report best-effort
if command -v tailscale >/dev/null 2>&1; then
  ok "tailscale CLI present"
  tailscale status 2>/dev/null | head -5 || true
else
  skip "tailscale CLI not in this container (expected if sidecar-only)"
fi

echo
if [[ "${rc}" -eq 0 ]]; then
  echo "doctor: base checks passed"
else
  echo "doctor: some required checks failed" >&2
fi
exit "${rc}"
