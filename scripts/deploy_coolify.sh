#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy_coolify.sh [--no-push] [--force] [--instant] [--skip-verify]

Important:
  Commit and push the work first. coolify_ex deploys the GitHub repo state,
  not your local uncommitted working tree.

Required environment variables:
  COOLIFY_BASE_URL   Example: https://coolify.example.com
  COOLIFY_TOKEN      Coolify API token with write access
  COOLIFY_APP_UUID   Coolify application UUID

Optional environment variables:
This wrapper runs the real deploy command from the nested Mix app:
  cd jido_hive_server
  MIX_ENV=coolify mix coolify.deploy

Useful follow-up commands:
  cd jido_hive_server
  MIX_ENV=coolify mix coolify.latest --project server
  MIX_ENV=coolify mix coolify.logs --project server --latest --tail 200
  MIX_ENV=coolify mix coolify.app_logs --project server --lines 200 --follow

Readiness / verification:
  The deploy manifest waits for GET /healthz, then verifies / and /api/targets.

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
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
}

require_cmd() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: ${name}" >&2
    exit 1
  fi
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
done

require_env COOLIFY_BASE_URL
require_env COOLIFY_TOKEN
require_env COOLIFY_APP_UUID

repo_root="$(git rev-parse --show-toplevel)"
server_root="${repo_root}/jido_hive_server"

cd "$server_root"
mix deps.get --only coolify

exec env MIX_ENV=coolify mix coolify.deploy "$@"
