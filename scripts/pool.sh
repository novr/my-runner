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
# Normalize to lowercase so names match prune filters (novr/Rin vs novr/rin).
if [[ -n "${GITHUB_ORG:-}" ]]; then
  TARGET="$(printf '%s' "${GITHUB_ORG}" | tr '[:upper:]' '[:lower:]')"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  TARGET="$(printf '%s' "${GITHUB_REPO}" | tr '/' '-' | tr '[:upper:]' '[:lower:]')"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2; exit 1
fi

POOL_SIZE="${POOL_SIZE:-2}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
BACKOFF_BASE="${BACKOFF_BASE:-30}"
BACKOFF_MAX="${BACKOFF_MAX:-600}"

# PIDs of in-flight spawn.sh processes (counted toward pool capacity).
SPAWN_PIDS=()
FAILURES=0
NEXT_SPAWN_AT=0

log() { echo "[$(date +%T)] [pool:${TARGET}] $*"; }

# tart list columns: Source | Name | Disk | Size | Accessed | State
running_vms() {
  tart list 2>/dev/null | awk -v p="${TARGET}-runner-" '$2 ~ ("^" p) { c++ } END { print c+0 }'
}

# Drop finished spawn PIDs; update failure streak for backoff.
reap_spawns() {
  local alive=()
  local pid status now
  now=$(date +%s)
  for pid in ${SPAWN_PIDS[@]+"${SPAWN_PIDS[@]}"}; do
    if kill -0 "${pid}" 2>/dev/null; then
      alive+=("${pid}")
      continue
    fi
    status=0
    wait "${pid}" || status=$?
    if [[ "${status}" -eq 0 ]]; then
      FAILURES=0
      NEXT_SPAWN_AT=0
    else
      FAILURES=$((FAILURES + 1))
      local shift=$(( FAILURES - 1 ))
      if [[ "${shift}" -gt 8 ]]; then shift=8; fi
      local delay=$(( BACKOFF_BASE * (1 << shift) ))
      if [[ "${delay}" -gt "${BACKOFF_MAX}" ]]; then
        delay="${BACKOFF_MAX}"
      fi
      NEXT_SPAWN_AT=$(( now + delay ))
      log "Spawn ${pid} exited ${status}; backoff ${delay}s (failures=${FAILURES})"
    fi
  done
  SPAWN_PIDS=(${alive[@]+"${alive[@]}"})
}

inflight_count() {
  echo "${#SPAWN_PIDS[@]}"
}

capacity() {
  echo $(( $(running_vms) + $(inflight_count) ))
}

log "Starting (target size: ${POOL_SIZE})..."

while true; do
  reap_spawns
  CURRENT=$(capacity)
  NEEDED=$(( POOL_SIZE - CURRENT ))
  NOW=$(date +%s)

  if [[ $NEEDED -gt 0 ]]; then
    if [[ "${FAILURES}" -gt 0 && "${NOW}" -lt "${NEXT_SPAWN_AT}" ]]; then
      log "Pool: ${CURRENT}/${POOL_SIZE}. Backing off $(( NEXT_SPAWN_AT - NOW ))s after failures..."
    else
      log "Pool: ${CURRENT}/${POOL_SIZE}. Spawning ${NEEDED} runner(s)..."
      for _ in $(seq 1 "${NEEDED}"); do
        "${REPO_ROOT}/scripts/spawn.sh" ${SPAWN_ARGS[@]+"${SPAWN_ARGS[@]}"} &
        SPAWN_PIDS+=("$!")
      done
    fi
  fi

  sleep "${CHECK_INTERVAL}"
done
