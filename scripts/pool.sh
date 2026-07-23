#!/usr/bin/env bash
# Maintains a pool of ephemeral runner VMs.
# Keeps POOL_SIZE runners listening at all times; spawns replacements as jobs complete.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../.env
[[ -f "${REPO_ROOT}/.env" ]] && source "${REPO_ROOT}/.env"

POOL_SIZE="${POOL_SIZE:-2}"
CHECK_INTERVAL=30  # seconds between pool size checks

log() { echo "[$(date +%T)] [pool] $*"; }

running_count() {
  tart list 2>/dev/null | grep -c "^runner-" || true
}

log "Starting pool manager (target size: ${POOL_SIZE})..."

while true; do
  CURRENT=$(running_count)
  NEEDED=$(( POOL_SIZE - CURRENT ))

  if [[ $NEEDED -gt 0 ]]; then
    log "Pool: ${CURRENT}/${POOL_SIZE}. Spawning ${NEEDED} runner(s)..."
    for _ in $(seq 1 "${NEEDED}"); do
      "${REPO_ROOT}/scripts/spawn.sh" &
    done
  fi

  sleep "${CHECK_INTERVAL}"
done
