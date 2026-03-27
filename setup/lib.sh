#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${JIDO_HIVE_SETUP_LIB_SH:-}" ]]; then
  return 0
fi

JIDO_HIVE_SETUP_LIB_SH=1
export JIDO_HIVE_SETUP_LIB_SH

IFS=$'\n\t'

JIDO_HIVE_API_BASE="${JIDO_HIVE_API_BASE:-http://127.0.0.1:4000/api}"
JIDO_HIVE_TENANT_ID="${JIDO_HIVE_TENANT_ID:-workspace-local}"
JIDO_HIVE_ACTOR_ID="${JIDO_HIVE_ACTOR_ID:-operator-1}"

log() {
  printf '[jido_hive setup] %s\n' "$*" >&2
}

die() {
  printf '[jido_hive setup] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_base_tools() {
  require_command curl
  require_command jq
}

json_print_file() {
  local file="$1"
  jq . "$file"
}

request_json() {
  local method="$1"
  local url="$2"
  local payload="$3"
  shift 3 || true

  local body_file
  body_file="$(mktemp)"

  local -a curl_args=(
    -sS
    -o "$body_file"
    -w '%{http_code}'
    -X "$method"
    "$url"
    -H 'accept: application/json'
  )

  if (($# > 0)); then
    curl_args+=("$@")
  fi

  if [[ -n "$payload" ]]; then
    curl_args+=(
      -H 'content-type: application/json'
      --data "$payload"
    )
  fi

  local status
  status="$(curl "${curl_args[@]}")"

  if [[ ! "$status" =~ ^[0-9]{3}$ ]]; then
    rm -f "$body_file"
    die "unexpected HTTP status from $method $url: $status"
  fi

  if (( status < 200 || status >= 300 )); then
    log "$method $url failed with HTTP $status"
    json_print_file "$body_file" >&2 || cat "$body_file" >&2
    rm -f "$body_file"
    exit 1
  fi

  json_print_file "$body_file"
  rm -f "$body_file"
}

api_get() {
  local path="$1"
  shift || true
  request_json GET "${JIDO_HIVE_API_BASE}${path}" "" "$@"
}

api_post() {
  local path="$1"
  local payload="$2"
  shift 2 || true
  request_json POST "${JIDO_HIVE_API_BASE}${path}" "$payload" "$@"
}

prompt_secret() {
  local prompt="$1"
  local secret=''

  [[ -t 0 ]] || die "no interactive terminal available; set JIDO_HIVE_ACCESS_TOKEN or use --access-token"

  read -r -s -p "$prompt" secret
  printf '\n' >&2

  [[ -n "$secret" ]] || die "secret cannot be empty"
  printf '%s\n' "$secret"
}

default_subject_for_connector() {
  local connector_id="$1"

  case "$connector_id" in
    github)
      printf '%s\n' "${JIDO_HIVE_GITHUB_SUBJECT:-octocat}"
      ;;

    notion)
      printf '%s\n' "${JIDO_HIVE_NOTION_SUBJECT:-notion-workspace}"
      ;;

    *)
      die "unsupported connector: $connector_id"
      ;;
  esac
}
