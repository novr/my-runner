#!/usr/bin/env bash
# Runs inside the Tart VM via SSH.
# Downloads the GitHub Actions runner (if not cached), registers via JIT config,
# executes one job, then shuts down the VM.
# Usage: bootstrap.sh <encoded_jit_config>
set -euo pipefail

JIT_CONFIG="${1:?JIT config required}"
RUNNER_VERSION="${RUNNER_VERSION:-2.322.0}"
RUNNER_DIR="${HOME}/actions-runner"
ARCHIVE="actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

if [[ ! -f "./run.sh" ]]; then
  echo "[bootstrap] Downloading runner v${RUNNER_VERSION}..."
  curl -fsSL \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}" \
    -o "${ARCHIVE}"
  tar xzf "${ARCHIVE}"
  rm "${ARCHIVE}"
fi

echo "[bootstrap] Starting runner..."
# --jitconfig: single-use JIT registration; runner deregisters itself after one job
./run.sh --jitconfig "${JIT_CONFIG}"

echo "[bootstrap] Runner finished. Shutting down VM..."
sudo shutdown -h now
