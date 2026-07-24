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
# Normalize to lowercase so prune/prefix matching stays consistent (novr/Rin vs novr/rin).
if [[ -n "${GITHUB_ORG:-}" ]]; then
  TARGET="$(printf '%s' "${GITHUB_ORG}" | tr '[:upper:]' '[:lower:]')"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  TARGET="$(printf '%s' "${GITHUB_REPO}" | tr '/' '-' | tr '[:upper:]' '[:lower:]')"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2; exit 1
fi

RUNNER_NAME="${TARGET}-runner-$(uuidgen | tr '[:upper:]' '[:lower:]')"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-xcode:latest}"
VM_CPU="${VM_CPU:-4}"
VM_MEMORY="${VM_MEMORY:-8192}"
VM_USER="${VM_USER:-admin}"
VM_PASSWORD="${VM_PASSWORD:-admin}"
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o NumberOfPasswordPrompts=1
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=10
)
SSH_CMD=(sshpass -p "${VM_PASSWORD}" ssh "${SSH_OPTS[@]}")
SCP_CMD=(sshpass -p "${VM_PASSWORD}" scp "${SSH_OPTS[@]}")
VM_PID=""
RUNNER_ID=""

log() { echo "[$(date +%T)] [${RUNNER_NAME}] $*"; }

cleanup() {
  # generate-jitconfig registers immediately; ephemeral self-remove only happens
  # after a completed job. Always best-effort DELETE (404 if already gone).
  if [[ -n "${RUNNER_ID}" ]]; then
    log "Ensuring runner id=${RUNNER_ID} is unregistered..."
    "${REPO_ROOT}/runner/delete-runner.sh" "${RUNNER_ID}" 2>/dev/null || true
  fi
  if [[ -n "${VM_PID}" ]] && kill -0 "${VM_PID}" 2>/dev/null; then
    log "Stopping tart run (pid ${VM_PID})..."
    kill "${VM_PID}" 2>/dev/null || true
    wait "${VM_PID}" 2>/dev/null || true
  fi
  if tart list 2>/dev/null | awk -v n="${RUNNER_NAME}" '$2 == n { found=1 } END { exit !found }'; then
    log "Stopping VM..."
    tart stop "${RUNNER_NAME}" 2>/dev/null || true
    log "Deleting VM..."
    tart delete "${RUNNER_NAME}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log "Cloning ${BASE_IMAGE}..."
tart clone "${BASE_IMAGE}" "${RUNNER_NAME}"
tart set "${RUNNER_NAME}" --cpu "${VM_CPU}" --memory "${VM_MEMORY}"

log "Starting VM (headless)..."
tart run "${RUNNER_NAME}" --no-graphics &
VM_PID=$!

log "Waiting for SSH to become available..."
VM_IP=$(tart ip "${RUNNER_NAME}" --wait 60)
log "VM IP: ${VM_IP}"

for i in $(seq 1 30); do
  "${SSH_CMD[@]}" "${VM_USER}@${VM_IP}" true 2>/dev/null && break
  [[ $i -eq 30 ]] && { log "SSH timeout"; exit 1; }
  sleep 2
done

log "Copying bootstrap script..."
"${SCP_CMD[@]}" "${REPO_ROOT}/runner/bootstrap.sh" "${VM_USER}@${VM_IP}:~/bootstrap.sh"

# Register with GitHub only after SSH works, to avoid offline orphan runners.
log "Fetching JIT config..."
JIT_JSON=$("${REPO_ROOT}/runner/jit-config.sh" "${RUNNER_NAME}")
RUNNER_ID=$(echo "${JIT_JSON}" | jq -r '.runner_id')
JIT_CONFIG=$(echo "${JIT_JSON}" | jq -r '.encoded_jit_config')
[[ -n "${RUNNER_ID}" && "${RUNNER_ID}" != "null" ]] || { log "ERROR: missing runner_id"; exit 1; }
[[ -n "${JIT_CONFIG}" && "${JIT_CONFIG}" != "null" ]] || { log "ERROR: missing encoded_jit_config"; exit 1; }

log "Starting runner inside VM (GitHub id=${RUNNER_ID})..."
# Pass JIT config via stdin so it never appears in process args (ps).
# Success path: bootstrap shuts down the VM → SSH often exits 255 (connection closed).
# Failure path: bootstrap exits 1 without shutdown → SSH exits 1.
ssh_status=0
printf '%s\n' "${JIT_CONFIG}" | "${SSH_CMD[@]}" "${VM_USER}@${VM_IP}" \
  "RUNNER_VERSION='${RUNNER_VERSION:-2.336.0}' bash ~/bootstrap.sh" || ssh_status=$?
if [[ "${ssh_status}" -eq 1 ]]; then
  log "ERROR: bootstrap failed inside VM"
  exit 1
fi

log "Waiting for VM to shut down..."
wait "${VM_PID}" || true
VM_PID=""
log "Done."
