#!/usr/bin/env bash
# Fetches a single-use JIT runner registration config from GitHub API.
# Outputs the encoded_jit_config string to stdout.
# Usage: jit-config.sh <runner-name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RUNNER_NAME="${1:?runner name required}"
LABELS="${RUNNER_LABELS:-macos,tart,xcode,self-hosted}"
GROUP_ID="${RUNNER_GROUP_ID:-1}"

# Obtain a short-lived installation access token from GitHub App credentials
TOKEN=$("${SCRIPT_DIR}/github-token.sh")

LABELS_JSON=$(echo "$LABELS" | tr ',' '\n' | jq -R . | jq -s .)

PAYLOAD=$(jq -n \
  --arg     name      "$RUNNER_NAME" \
  --argjson group_id  "$GROUP_ID" \
  --argjson labels    "$LABELS_JSON" \
  '{name: $name, runner_group_id: $group_id, labels: $labels, work_folder: "_work"}')

if [[ -n "${GITHUB_ORG:-}" ]]; then
  ENDPOINT="https://api.github.com/orgs/${GITHUB_ORG}/actions/runners/generate-jitconfig"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  ENDPOINT="https://api.github.com/repos/${GITHUB_REPO}/actions/runners/generate-jitconfig"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2
  exit 1
fi

curl -fsSL \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -d "$PAYLOAD" \
  "$ENDPOINT" | jq -r '.encoded_jit_config'
