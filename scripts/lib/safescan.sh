#!/usr/bin/env bash

# SafeScan helpers.

cocoloop_safescan_report() {
  local skill_hash="${1:-}"
  cocoloop_api_get "$(cocoloop_api_base_url)/safescan/report/${skill_hash}"
}

cocoloop_safescan_report_batch() {
  local payload="{\"skill_hashes\":["
  local first=1
  local hash
  for hash in "$@"; do
    if [[ $first -eq 0 ]]; then
      payload+=','
    fi
    payload+="\"${hash}\""
    first=0
  done
  payload+=']} '
  payload="${payload% }"
  cocoloop_api_post "$(cocoloop_api_base_url)/safescan/report-batch" "$payload"
}

cocoloop_safescan_check_existence() {
  local payload="{\"skill_hashes\":["
  local first=1
  local hash
  for hash in "$@"; do
    if [[ $first -eq 0 ]]; then
      payload+=','
    fi
    payload+="\"${hash}\""
    first=0
  done
  payload+=']} '
  payload="${payload% }"
  cocoloop_api_post "$(cocoloop_api_base_url)/safescan/check-existence" "$payload"
}

cocoloop_safescan_upload_file() {
  local file_path="${1:-}"
  local snowflake_id="${2:-local-$(date +%s)}"
  [[ -f "$file_path" ]] || {
    echo "SafeScan 上传失败：文件不存在: $file_path" >&2
    return 1
  }

  curl --silent --show-error --location --max-time "$(cocoloop_api_timeout)" \
    -X POST "$(cocoloop_api_base_url)/safescan/upload" \
    -F "upload_type=file" \
    -F "snowflake_id=${snowflake_id}" \
    -F "file=@${file_path}"
}

cocoloop_safescan_upload_directory() {
  local dir_path="${1:-}"
  local snowflake_id="${2:-local-$(date +%s)}"
  [[ -d "$dir_path" ]] || {
    echo "SafeScan 上传失败：目录不存在: $dir_path" >&2
    return 1
  }

  curl --silent --show-error --location --max-time "$(cocoloop_api_timeout)" \
    -X POST "$(cocoloop_api_base_url)/safescan/upload" \
    -F "upload_type=path" \
    -F "snowflake_id=${snowflake_id}" \
    -F "file_paths[]=${dir_path}"
}

cocoloop_safescan_agent_paths() {
  local agent_name="${1:-codex}"
  local os_platform="${2:-macos}"
  cocoloop_api_agent_skill_paths "$agent_name" "$os_platform"
}
