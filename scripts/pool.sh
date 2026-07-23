#!/usr/bin/env bash
# Maintains a pool of ephemeral runner VMs.
# Keeps POOL_SIZE runners listening at all times; spawns replacements as jobs complete.
#
# Usage:
#   pool.sh                        # use GITHUB_ORG / GITHUB_REPO from .env
#   pool.sh --repo owner/repo      # repo-level pool (overrides .env)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${REPO_ROOT}/.env" ]] && source "${REPO_ROOT}/.env"

# ── Argument parsing ──────────────────────────────────────────────────────────
SPAWN_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) GITHUB_REPO="$2"; unset GITHUB_ORG; SPAWN_ARGS=(--repo "$2"); shift 2 ;;
    *)      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Determine name prefix to scope VM count to this target ───────────────────
if [[ -n "${GITHUB_ORG:-}" ]]; then
  TARGET="${GITHUB_ORG}"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  TARGET="$(echo "${GITHUB_REPO}" | tr '/' '-')"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2; exit 1
fi

POOL_SIZE="${POOL_SIZE:-2}"
CHECK_INTERVAL=30

log() { echo "[$(date +%T)] [pool:${TARGET}] $*"; }

running_count() {
  tart list 2>/dev/null | grep -c "^${TARGET}-runner-" || true
}

log "Starting (target size: ${POOL_SIZE})..."

while true; do
  CURRENT=$(running_count)
  NEEDED=$(( POOL_SIZE - CURRENT ))

  if [[ $NEEDED -gt 0 ]]; then
    log "Pool: ${CURRENT}/${POOL_SIZE}. Spawning ${NEEDED} runner(s)..."
    for _ in $(seq 1 "${NEEDED}"); do
      "${REPO_ROOT}/scripts/spawn.sh" "${SPAWN_ARGS[@]}" &
    done
  fi

  sleep "${CHECK_INTERVAL}"
done
