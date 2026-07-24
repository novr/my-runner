#!/usr/bin/env bash
# Deletes a registered self-hosted runner by ID (best-effort).
# Usage: delete-runner.sh <runner-id>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_ID="${1:?runner id required}"

TOKEN=$("${SCRIPT_DIR}/github-token.sh")

if [[ -n "${GITHUB_ORG:-}" ]]; then
  ENDPOINT="https://api.github.com/orgs/${GITHUB_ORG}/actions/runners/${RUNNER_ID}"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  ENDPOINT="https://api.github.com/repos/${GITHUB_REPO}/actions/runners/${RUNNER_ID}"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2
  exit 1
fi

curl -fsSL \
  -X DELETE \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$ENDPOINT" >/dev/null
