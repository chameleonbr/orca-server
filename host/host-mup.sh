#!/usr/bin/env bash
# host-mup.sh — run mup inside the orca container from the Docker HOST
# Use with cron or systemd timer. Safe to run while stack is up.
#
# Env (optional):
#   ORCA_COMPOSE_DIR   default: directory containing this repo's compose file
#   ORCA_SERVICE       default: orca
#   ORCA_CONTAINER     default: orca-server
#   MUP_RESTART_ORCA   default: true — restart orca service if binary changed
#   COMPOSE_FILE       extra compose files, space-separated
set -euo pipefail

log() { printf '[host-mup] %s\n' "$*"; }

# Resolve compose project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${ORCA_COMPOSE_DIR:-${ROOT_DIR}}"
SERVICE="${ORCA_SERVICE:-orca}"
CONTAINER="${ORCA_CONTAINER:-orca-server}"
RESTART="${MUP_RESTART_ORCA:-true}"

cd "${COMPOSE_DIR}"

compose() {
  if [[ -n "${COMPOSE_FILE:-}" ]]; then
    # shellcheck disable=SC2086
    docker compose ${COMPOSE_FILE} "$@"
  else
    docker compose "$@"
  fi
}

# Prefer compose exec; fall back to docker exec by container name
run_mup() {
  if compose ps --status running --services 2>/dev/null | grep -qx "${SERVICE}"; then
    compose exec -T "${SERVICE}" /scripts/mup.sh
    return $?
  fi
  if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    docker exec "${CONTAINER}" /scripts/mup.sh
    return $?
  fi
  log "ERROR: orca container not running (service=${SERVICE} container=${CONTAINER})"
  log "Start the stack first: docker compose up -d"
  return 1
}

log "Running mup in orca container…"
rc=0
run_mup || rc=$?

# Restart if Orca binary changed
if [[ "${RESTART}" == "true" ]]; then
  needs=""
  if compose ps --status running --services 2>/dev/null | grep -qx "${SERVICE}"; then
    needs="$(compose exec -T "${SERVICE}" bash -c 'cat /home/orca/.local/state/orca-agent-manager/orca-restart-needed 2>/dev/null || true' || true)"
  elif docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    needs="$(docker exec "${CONTAINER}" bash -c 'cat /home/orca/.local/state/orca-agent-manager/orca-restart-needed 2>/dev/null || true' || true)"
  fi
  if [[ "${needs}" == "1" ]]; then
    log "Orca binary changed — restarting ${SERVICE}…"
    if compose ps --status running --services 2>/dev/null | grep -qx "${SERVICE}"; then
      compose restart "${SERVICE}"
    else
      docker restart "${CONTAINER}"
    fi
    # clear flag
    docker exec "${CONTAINER}" bash -c 'rm -f /home/orca/.local/state/orca-agent-manager/orca-restart-needed' 2>/dev/null || true
    log "Restart done"
  else
    log "No Orca restart needed"
  fi
fi

exit "${rc}"
