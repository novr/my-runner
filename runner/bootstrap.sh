#!/usr/bin/env bash
# Runs inside the Tart VM via SSH.
# Downloads the GitHub Actions runner (if missing or wrong version), registers via
# JIT config from stdin, executes one job, then shuts down the VM.
# Usage: printf '%s\n' "$encoded_jit_config" | bootstrap.sh
set -euo pipefail

JIT_CONFIG="$(cat)"
[[ -n "${JIT_CONFIG}" ]] || { echo "ERROR: JIT config required on stdin" >&2; exit 1; }

RUNNER_VERSION="${RUNNER_VERSION:-2.336.0}"
RUNNER_DIR="${HOME}/actions-runner"
ARCHIVE="actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"
MARKER="${RUNNER_DIR}/.runner-version"

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

need_download=false
if [[ ! -f "./run.sh" ]]; then
  need_download=true
elif [[ ! -f "${MARKER}" ]] || [[ "$(cat "${MARKER}")" != "${RUNNER_VERSION}" ]]; then
  need_download=true
fi

if [[ "${need_download}" == true ]]; then
  echo "[bootstrap] Downloading runner v${RUNNER_VERSION}..."
  # Clear previous install bits that would conflict with a version swap.
  find . -mindepth 1 -maxdepth 1 ! -name '_work' ! -name '_diag' -exec rm -rf {} +
  curl -fsSL \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ARCHIVE}" \
    -o "${ARCHIVE}"
  tar xzf "${ARCHIVE}"
  rm "${ARCHIVE}"
  printf '%s\n' "${RUNNER_VERSION}" > "${MARKER}"
fi

echo "[bootstrap] Starting runner v${RUNNER_VERSION}..."
# --jitconfig: single-use JIT registration; runner deregisters itself after one job
if ! ./run.sh --jitconfig "${JIT_CONFIG}"; then
  echo "[bootstrap] ERROR: runner exited with failure (check version / network)" >&2
  exit 1
fi

echo "[bootstrap] Runner finished. Shutting down VM..."
sudo shutdown -h now
