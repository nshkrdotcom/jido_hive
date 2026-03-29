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

Optional environment variables:
  JIDO_OS_DEPLOY_KEY_PATH  Local SSH private key path for nshkrdotcom/jido_os
                           Default: ~/.ssh/id_ed25519_jido_os_nshkrdotcom_fork_deploy

This wrapper runs the real deploy command from the nested Mix app:
  cd jido_hive_server
  MIX_ENV=dev mix coolify.deploy

Useful follow-up commands:
  cd jido_hive_server
  MIX_ENV=dev mix coolify.latest --project server
  MIX_ENV=dev mix coolify.logs --project server --latest --tail 200
  MIX_ENV=dev mix coolify.app_logs --project server --lines 200 --follow

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

sync_jido_os_deploy_key() {
  local key_path="${JIDO_OS_DEPLOY_KEY_PATH:-$HOME/.ssh/id_ed25519_jido_os_nshkrdotcom_fork_deploy}"

  if [[ ! -f "$key_path" ]]; then
    echo "Missing jido_os deploy key: ${key_path}" >&2
    exit 1
  fi

  require_cmd curl
  require_cmd jq

  local api_base="${COOLIFY_BASE_URL%/}/api/v1"
  local envs_json payload method
  envs_json="$(
    curl -fsS \
      -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
      -H "Accept: application/json" \
      "${api_base}/applications/${COOLIFY_APP_UUID}/envs"
  )"

  method="POST"
  if jq -e '.[] | select(.key == "JIDO_OS_DEPLOY_KEY" and (.is_preview | not))' >/dev/null <<<"$envs_json"; then
    method="PATCH"
  fi

  payload="$(
    jq -n --rawfile value "$key_path" '{
      key: "JIDO_OS_DEPLOY_KEY",
      value: $value,
      is_preview: false,
      is_literal: true,
      is_multiline: true,
      is_shown_once: false,
      is_buildtime: true,
      is_runtime: false
    }'
  )"

  curl -fsS \
    -X "$method" \
    -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${api_base}/applications/${COOLIFY_APP_UUID}/envs" >/dev/null

  envs_json="$(
    curl -fsS \
      -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
      -H "Accept: application/json" \
      "${api_base}/applications/${COOLIFY_APP_UUID}/envs"
  )"

  if ! jq -e '.[] | select(.key == "JIDO_OS_DEPLOY_KEY" and (.is_preview | not))' >/dev/null <<<"$envs_json"; then
    echo "Failed to sync JIDO_OS_DEPLOY_KEY to Coolify" >&2
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

sync_jido_os_deploy_key

repo_root="$(git rev-parse --show-toplevel)"
server_root="${repo_root}/jido_hive_server"

cd "$server_root"
mix deps.get --only dev

exec env MIX_ENV=dev mix coolify.deploy "$@"
