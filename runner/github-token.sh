#!/usr/bin/env bash
# Generates a GitHub App installation access token (valid ~1 hour).
# Outputs the token to stdout.
#
# Required env vars:
#   GITHUB_APP_ID               — App ID (numeric, shown on app settings page)
#   GITHUB_APP_INSTALLATION_ID  — Installation ID (see: gh api /orgs/{org}/installation)
#   GITHUB_APP_PRIVATE_KEY_PATH — Path to the .pem private key file
set -euo pipefail

: "${GITHUB_APP_ID:?}"
: "${GITHUB_APP_INSTALLATION_ID:?}"
: "${GITHUB_APP_PRIVATE_KEY_PATH:?}"

b64url() {
  printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '='
}

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
