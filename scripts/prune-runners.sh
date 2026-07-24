#!/usr/bin/env bash
# Removes offline self-hosted runners left behind by failed/aborted JIT spawns.
#
# Usage:
#   prune-runners.sh                 # use GITHUB_ORG / GITHUB_REPO from .env
#   prune-runners.sh --repo owner/repo
#   prune-runners.sh --dry-run
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "${REPO_ROOT}/.env" ]] && source "${REPO_ROOT}/.env"

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) GITHUB_REPO="$2"; unset GITHUB_ORG; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "${GITHUB_ORG:-}" ]]; then
  LIST_PATH="/orgs/${GITHUB_ORG}/actions/runners"
  PREFIX="${GITHUB_ORG}-runner-"
elif [[ -n "${GITHUB_REPO:-}" ]]; then
  LIST_PATH="/repos/${GITHUB_REPO}/actions/runners"
  PREFIX="$(echo "${GITHUB_REPO}" | tr '/' '-')-runner-"
else
  echo "ERROR: GITHUB_ORG or GITHUB_REPO must be set" >&2
  exit 1
fi

TOKEN=$("${REPO_ROOT}/runner/github-token.sh")
export TOKEN LIST_PATH PREFIX DRY_RUN REPO_ROOT GITHUB_ORG GITHUB_REPO

log() { echo "[$(date +%T)] [prune] $*"; }

page=1
deleted=0
while true; do
  RESP=$(curl -fsSL \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com${LIST_PATH}?per_page=100&page=${page}")

  COUNT=$(echo "$RESP" | jq '.runners | length')
  [[ "${COUNT}" -eq 0 ]] && break

  while IFS=$'\t' read -r id name status; do
    [[ -z "${id}" ]] && continue
    if [[ "${DRY_RUN}" == true ]]; then
      log "Would delete offline runner ${name} (id=${id})"
    else
      log "Deleting offline runner ${name} (id=${id})..."
      GITHUB_ORG="${GITHUB_ORG:-}" GITHUB_REPO="${GITHUB_REPO:-}" \
        "${REPO_ROOT}/runner/delete-runner.sh" "${id}" || true
    fi
    deleted=$((deleted + 1))
  done < <(echo "$RESP" | jq -r --arg p "${PREFIX}" '
    .runners[]
    | select(.status == "offline")
    | select(.name | startswith($p))
    | [.id, .name, .status]
    | @tsv
  ')

  [[ "${COUNT}" -lt 100 ]] && break
  page=$((page + 1))
done

log "Done. ${deleted} offline runner(s) processed."
