#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy_coolify.sh [--no-push] [--force] [--instant]

Required environment variables:
  COOLIFY_BASE_URL   Example: https://coolify.example.com
  COOLIFY_TOKEN      Coolify API token with write access
  COOLIFY_APP_UUID   Coolify application UUID

Optional environment variables:
  GIT_REMOTE         Default: origin
  GIT_BRANCH         Default: main
  POLL_INTERVAL      Default: 3
  POLL_TIMEOUT       Default: 900

Examples:
  export COOLIFY_BASE_URL="https://coolify.example.com"
  export COOLIFY_TOKEN="..."
  export COOLIFY_APP_UUID="h1bcqanqe3icgd4sgypcrvol"
  scripts/deploy_coolify.sh

  scripts/deploy_coolify.sh --no-push --force
EOF
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

push_git=true
force=false
instant=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-push)
      push_git=false
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --instant)
      instant=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_env COOLIFY_BASE_URL
require_env COOLIFY_TOKEN
require_env COOLIFY_APP_UUID

GIT_REMOTE="${GIT_REMOTE:-origin}"
GIT_BRANCH="${GIT_BRANCH:-main}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"
POLL_TIMEOUT="${POLL_TIMEOUT:-900}"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ "$push_git" == "true" ]]; then
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "$GIT_BRANCH" ]]; then
    echo "Current branch is '$current_branch', expected '$GIT_BRANCH'." >&2
    exit 1
  fi

  echo "Pushing ${GIT_REMOTE}/${GIT_BRANCH}..."
  git push "$GIT_REMOTE" "$GIT_BRANCH"
fi

api_base="${COOLIFY_BASE_URL%/}/api/v1"
start_url="${api_base}/applications/${COOLIFY_APP_UUID}/start?force=${force}&instant_deploy=${instant}"

echo "Triggering Coolify deployment..."
response="$(
  curl --silent --show-error --fail \
    --request GET \
    --header "Authorization: Bearer ${COOLIFY_TOKEN}" \
    --header "Accept: application/json" \
    "$start_url"
)"

deployment_uuid="$(
  printf '%s' "$response" | sed -n 's/.*"deployment_uuid":"\([^"]*\)".*/\1/p'
)"

if [[ -z "$deployment_uuid" ]]; then
  echo "Could not parse deployment UUID from response:" >&2
  echo "$response" >&2
  exit 1
fi

echo "Deployment queued: ${deployment_uuid}"

status_url="${api_base}/deployments/${deployment_uuid}"
started_at="$(date +%s)"

while true; do
  status_response="$(
    curl --silent --show-error --fail \
      --header "Authorization: Bearer ${COOLIFY_TOKEN}" \
      --header "Accept: application/json" \
      "$status_url"
  )"

  status="$(printf '%s' "$status_response" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
  deployment_url="$(printf '%s' "$status_response" | sed -n 's/.*"deployment_url":"\([^"]*\)".*/\1/p')"

  printf 'Status: %s\n' "${status:-unknown}"

  case "$status" in
    finished|success)
      [[ -n "$deployment_url" ]] && printf 'Logs: %s\n' "$deployment_url"
      exit 0
      ;;
    failed|canceled|cancelled|error)
      [[ -n "$deployment_url" ]] && printf 'Logs: %s\n' "$deployment_url"
      exit 1
      ;;
  esac

  now="$(date +%s)"
  if (( now - started_at > POLL_TIMEOUT )); then
    echo "Timed out waiting for deployment." >&2
    [[ -n "$deployment_url" ]] && printf 'Logs: %s\n' "$deployment_url" >&2
    exit 1
  fi

  sleep "$POLL_INTERVAL"
done
