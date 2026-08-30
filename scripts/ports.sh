#!/usr/bin/env bash
# ports.sh — list listening ports in the shared network namespace
set -euo pipefail

echo "PORT   PROCESS (best effort)"
echo "----------------------------"

if command -v ss >/dev/null 2>&1; then
  ss -lntp 2>/dev/null | awk 'NR==1 || /LISTEN/' || ss -lnt
  exit 0
fi

if command -v netstat >/dev/null 2>&1; then
  netstat -lntp 2>/dev/null || netstat -lnt
  exit 0
fi

echo "Neither ss nor netstat available" >&2
exit 1
