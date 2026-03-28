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
JIDO_HIVE_HTTP_STATUS=''
JIDO_HIVE_HTTP_BODY_FILE=''

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

cleanup_http_response() {
  if [[ -n "${JIDO_HIVE_HTTP_BODY_FILE:-}" && -f "$JIDO_HIVE_HTTP_BODY_FILE" ]]; then
    rm -f "$JIDO_HIVE_HTTP_BODY_FILE"
  fi

  JIDO_HIVE_HTTP_STATUS=''
  JIDO_HIVE_HTTP_BODY_FILE=''
}

perform_request() {
  local method="$1"
  local url="$2"
  local payload="$3"
  shift 3 || true

  cleanup_http_response

  local body_file
  body_file="$(mktemp)"
  local error_file
  error_file="$(mktemp)"

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

  local status=''
  if status="$(curl "${curl_args[@]}" 2>"$error_file")"; then
    rm -f "$error_file"
  else
    local curl_exit=$?
    local curl_error=''

    if [[ -s "$error_file" ]]; then
      curl_error="$(<"$error_file")"
    fi

    rm -f "$body_file" "$error_file"

    case "$curl_exit" in
      7)
        die "cannot reach $JIDO_HIVE_API_BASE; start the server with bin/server or set JIDO_HIVE_API_BASE"
        ;;

      *)
        if [[ -n "$curl_error" ]]; then
          die "request failed for $method $url: $curl_error"
        fi

        die "request failed for $method $url with curl exit code $curl_exit"
        ;;
    esac
  fi

  if [[ ! "$status" =~ ^[0-9]{3}$ ]]; then
    rm -f "$body_file"
    die "unexpected HTTP status from $method $url: $status"
  fi

  JIDO_HIVE_HTTP_STATUS="$status"
  JIDO_HIVE_HTTP_BODY_FILE="$body_file"
}

request_json() {
  local method="$1"
  local url="$2"
  local payload="$3"
  shift 3 || true

  perform_request "$method" "$url" "$payload" "$@"

  if (( JIDO_HIVE_HTTP_STATUS < 200 || JIDO_HIVE_HTTP_STATUS >= 300 )); then
    log "$method $url failed with HTTP $JIDO_HIVE_HTTP_STATUS"
    json_print_file "$JIDO_HIVE_HTTP_BODY_FILE" >&2 || cat "$JIDO_HIVE_HTTP_BODY_FILE" >&2
    cleanup_http_response
    exit 1
  fi

  json_print_file "$JIDO_HIVE_HTTP_BODY_FILE"
  cleanup_http_response
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

wait_for_api() {
  local timeout_ms="${1:-30000}"
  local interval_ms="${2:-250}"
  local deadline_ms

  deadline_ms=$(( $(date +%s%3N) + timeout_ms ))

  while true; do
    if curl -fsS -o /dev/null "${JIDO_HIVE_API_BASE}/targets" 2>/dev/null; then
      return 0
    fi

    if (( $(date +%s%3N) >= deadline_ms )); then
      die "cannot reach $JIDO_HIVE_API_BASE; start the server with bin/server or set JIDO_HIVE_API_BASE"
    fi

    sleep "$(awk "BEGIN { printf \"%.3f\", ${interval_ms}/1000 }")"
  done
}

wait_for_targets() {
  local timeout_ms="$1"
  local interval_ms="$2"
  shift 2 || true

  local -a target_ids=("$@")
  local deadline_ms

  ((${#target_ids[@]} > 0)) || die "wait_for_targets requires at least one target id"

  deadline_ms=$(( $(date +%s%3N) + timeout_ms ))

  while true; do
    local targets_json=''

    if targets_json="$(curl -fsS "${JIDO_HIVE_API_BASE}/targets" 2>/dev/null)"; then
      local missing=0
      local target_id=''

      for target_id in "${target_ids[@]}"; do
        if ! jq -e --arg target_id "$target_id" \
          '.data | any(.target_id == $target_id)' >/dev/null <<<"$targets_json"; then
          missing=1
          break
        fi
      done

      if (( missing == 0 )); then
        jq . <<<"$targets_json"
        return 0
      fi
    fi

    if (( $(date +%s%3N) >= deadline_ms )); then
      die "timed out waiting for targets: ${target_ids[*]}"
    fi

    sleep "$(awk "BEGIN { printf \"%.3f\", ${interval_ms}/1000 }")"
  done
}

fetch_targets_json() {
  curl -fsS "${JIDO_HIVE_API_BASE}/targets" 2>/dev/null
}

wait_for_target_count() {
  local timeout_ms="$1"
  local interval_ms="$2"
  local target_count="$3"
  local deadline_ms

  [[ -n "$target_count" ]] || die "wait_for_target_count requires a target count"
  deadline_ms=$(( $(date +%s%3N) + timeout_ms ))

  while true; do
    local targets_json=''

    if targets_json="$(fetch_targets_json)"; then
      if jq -e --argjson target_count "$target_count" \
        '.data | length >= $target_count' >/dev/null <<<"$targets_json"; then
        jq . <<<"$targets_json"
        return 0
      fi
    fi

    if (( $(date +%s%3N) >= deadline_ms )); then
      die "timed out waiting for at least $target_count targets"
    fi

    sleep "$(awk "BEGIN { printf \"%.3f\", ${interval_ms}/1000 }")"
  done
}
