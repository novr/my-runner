#!/usr/bin/env bash
# Installs prerequisites on the host Apple Silicon Mac.
# Run once before first use.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../.env
[[ -f "${REPO_ROOT}/.env" ]] && source "${REPO_ROOT}/.env"

install_if_missing() {
  local cmd="$1" formula="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo "Installing ${formula}..."
    brew install "$formula"
  else
    echo "${cmd} already installed."
  fi
}

install_if_missing tart   openai/tools/tart
install_if_missing sshpass hudochenkov/sshpass/sshpass
install_if_missing jq     jq

chmod +x "${REPO_ROOT}/runner/"*.sh "${REPO_ROOT}/scripts/"*.sh

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-xcode:latest}"
echo "Pulling base image: ${BASE_IMAGE} (this may take a while)..."
tart pull "${BASE_IMAGE}"

echo ""
echo "Host setup complete."
echo "Next: cp .env.example .env  # then fill in GITHUB_TOKEN and GITHUB_ORG"
