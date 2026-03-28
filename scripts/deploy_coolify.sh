#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy_coolify.sh [--no-push] [--force] [--instant] [--skip-verify]

Required environment variables:
  COOLIFY_BASE_URL   Example: https://coolify.example.com
  COOLIFY_TOKEN      Coolify API token with write access
  COOLIFY_APP_UUID   Coolify application UUID

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
mix deps.get --only dev
MIX_ENV=dev mix deps.compile coolify_ex

exec env MIX_ENV=dev mix coolify.deploy "$@"
