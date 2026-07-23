#!/usr/bin/env bash
# Spawns one ephemeral runner VM: clone → configure → register → run job → delete.
# Blocks until the job completes and the VM shuts down.
#
# Usage:
#   spawn.sh                        # use GITHUB_ORG / GITHUB_REPO from .env
#   spawn.sh --repo owner/repo      # repo-level runner (overrides .env)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${REPO_ROOT}/.env" ]] && source "${REPO_ROOT}/.env"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) GITHUB_REPO="$2"; unset GITHUB_ORG; shift 2 ;;
    *)      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Determine name prefix (used to namespace VMs per target) ──────────────────
if [[ -n "${GITHUB_ORG:-}" ]]; then
  TARGET="${GITHUB_ORG}"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  TARGET="$(echo "${GITHUB_REPO}" | tr '/' '-')"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2; exit 1
fi

RUNNER_NAME="${TARGET}-runner-$(uuidgen | tr '[:upper:]' '[:lower:]')"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-xcode:latest}"
VM_CPU="${VM_CPU:-4}"
VM_MEMORY="${VM_MEMORY:-8192}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 -o ServerAliveCountMax=10"

log() { echo "[$(date +%T)] [${RUNNER_NAME}] $*"; }

cleanup() {
  log "Deleting VM..."
  tart delete "${RUNNER_NAME}" 2>/dev/null || true
}
trap cleanup EXIT

log "Cloning ${BASE_IMAGE}..."
tart clone "${BASE_IMAGE}" "${RUNNER_NAME}"
tart set "${RUNNER_NAME}" --cpu "${VM_CPU}" --memory "${VM_MEMORY}"

log "Fetching JIT config..."
JIT_CONFIG=$("${REPO_ROOT}/runner/jit-config.sh" "${RUNNER_NAME}")

log "Starting VM (headless)..."
tart run "${RUNNER_NAME}" --no-graphics &
VM_PID=$!

log "Waiting for SSH to become available..."
VM_IP=$(tart ip "${RUNNER_NAME}" --wait 60)
log "VM IP: ${VM_IP}"

for i in $(seq 1 30); do
  ssh $SSH_OPTS "admin@${VM_IP}" true 2>/dev/null && break
  [[ $i -eq 30 ]] && { log "SSH timeout"; exit 1; }
  sleep 2
done

log "Copying bootstrap script..."
scp $SSH_OPTS "${REPO_ROOT}/runner/bootstrap.sh" "admin@${VM_IP}:~/bootstrap.sh"

log "Starting runner inside VM..."
# bootstrap.sh ends with `shutdown -h now`; SSH exits non-zero — expected
ssh $SSH_OPTS "admin@${VM_IP}" \
  "RUNNER_VERSION='${RUNNER_VERSION:-2.322.0}' bash ~/bootstrap.sh '${JIT_CONFIG}'" || true

log "Waiting for VM to shut down..."
wait "${VM_PID}" || true
log "Done."
