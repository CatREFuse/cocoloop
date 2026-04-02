#!/usr/bin/env bash

# Remote API helpers for Cocoloop CLI.

cocoloop_api_base_url() {
  printf '%s\n' "${COCOLOOP_API_BASE_URL:-https://api.cocoloop.cn/api/v1}"
}

cocoloop_api_timeout() {
  printf '%s\n' "${COCOLOOP_API_TIMEOUT:-20}"
}

cocoloop_api_has_jq() {
  command -v jq >/dev/null 2>&1
}

cocoloop_api_urlencode() {
  local value="${1:-}"
  if cocoloop_api_has_jq; then
    jq -rn --arg v "$value" '$v|@uri'
    return 0
  fi
  python3 - <<'PY' "$value"
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
}

cocoloop_api__curl() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  local curl_args=()

  curl_args+=(--silent --show-error --location --max-time "$(cocoloop_api_timeout)")
  curl_args+=(-X "$method" "$url")
  curl_args+=(-H 'Accept: application/json')

  if [[ -n "$data" ]]; then
    curl_args+=(-H 'Content-Type: application/json' --data "$data")
  fi

  curl "${curl_args[@]}"
}

cocoloop_api_get() {
  cocoloop_api__curl GET "$1"
}

cocoloop_api_post() {
  cocoloop_api__curl POST "$1" "${2:-}"
}

cocoloop_api_ping() {
  cocoloop_api_get "$(cocoloop_api_base_url)/health/ping"
}

cocoloop_api_healthcheck() {
  cocoloop_api_get "$(cocoloop_api_base_url)/health/"
}

cocoloop_api_search() {
  local query="${1:-}"
  local encoded
  encoded="$(cocoloop_api_urlencode "$query")"
  cocoloop_api_get "$(cocoloop_api_base_url)/store/skills?page=1&page_size=10&keyword=${encoded}&sort=downloads"
}

cocoloop_api_inspect_skill_by_id() {
  local skill_id="${1:-}"
  cocoloop_api_get "$(cocoloop_api_base_url)/store/skills/${skill_id}"
}

cocoloop_api_skill_files() {
  local skill_id="${1:-}"
  local version="${2:-latest}"
  local encoded
  encoded="$(cocoloop_api_urlencode "$version")"
  cocoloop_api_get "$(cocoloop_api_base_url)/store/skills/${skill_id}/files?version=${encoded}"
}

cocoloop_api_like() {
  local skill_name="${1:-}"
  local encoded
  encoded="$(cocoloop_api_urlencode "$skill_name")"
  cocoloop_api_post "$(cocoloop_api_base_url)/store/like?skill=${encoded}" '{}'
}

cocoloop_api_like_list() {
  cocoloop_api_get "$(cocoloop_api_base_url)/like-list"
}

cocoloop_api_candidate() {
  local raw_json="${1:-}"
  cocoloop_api_post "$(cocoloop_api_base_url)/store/candidate" "$raw_json"
}

cocoloop_api_behavior_report() {
  local object_id="${1:-}"
  local action="${2:-view}"
  local object_type="${3:-skill}"
  cocoloop_api_post \
    "$(cocoloop_api_base_url)/store/skills/action" \
    "{\"id\":${object_id},\"object_type\":\"${object_type}\",\"action\":\"${action}\"}"
}

cocoloop_api_agent_skill_paths() {
  local agent_name="${1:-codex}"
  local os_platform="${2:-macos}"
  local encoded_agent encoded_os
  encoded_agent="$(cocoloop_api_urlencode "$agent_name")"
  encoded_os="$(cocoloop_api_urlencode "$os_platform")"
  cocoloop_api_get "$(cocoloop_api_base_url)/safescan/agent-skill-paths?agent_name=${encoded_agent}&os_platform=${encoded_os}"
}

cocoloop_api_check_upgrade() {
  local client_version="${1:-0.0.0}"
  local os_platform="${2:-macos}"
  cocoloop_api_post \
    "$(cocoloop_api_base_url)/safescan/client/check-upgrade" \
    "{\"client_version\":\"${client_version}\",\"os_platform\":\"${os_platform}\"}"
}
