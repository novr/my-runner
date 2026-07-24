#!/usr/bin/env bash
# Returns a GitHub API token to stdout.
#
# Priority:
#   1. GitHub Apps  — if GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY_PATH are set
#      Generates a JWT, exchanges it for an Installation Access Token (~1 hour).
#      Required for launchd / non-interactive hosts (no keyring).
#   2. PAT          — if GITHUB_TOKEN is set
#      Returns it directly.
#   3. gh CLI       — interactive fallback only; fails under launchd.
set -euo pipefail

if [[ -n "${GITHUB_APP_ID:-}" && -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
  : "${GITHUB_APP_INSTALLATION_ID:?GITHUB_APP_INSTALLATION_ID must be set when using GitHub Apps}"

  b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '='; }

  now=$(date +%s)
  header=$(b64url '{"alg":"RS256","typ":"JWT"}')
  payload=$(b64url "{\"iat\":$((now - 60)),\"exp\":$((now + 600)),\"iss\":\"${GITHUB_APP_ID}\"}")
  signing_input="${header}.${payload}"
  signature=$(printf '%s' "${signing_input}" \
    | openssl dgst -sha256 -sign "${GITHUB_APP_PRIVATE_KEY_PATH}" \
    | base64 | tr '+/' '-_' | tr -d '=')
  jwt="${signing_input}.${signature}"

  curl -fsSL \
    -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
    | jq -r '.token'

elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  printf '%s' "${GITHUB_TOKEN}"

elif command -v gh &>/dev/null && gh auth status &>/dev/null; then
  gh auth token

else
  echo "ERROR: set either (GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY_PATH + GITHUB_APP_INSTALLATION_ID) or GITHUB_TOKEN" >&2
  exit 1
fi
