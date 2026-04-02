#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"
# shellcheck source=lib/install.sh
source "$SCRIPT_DIR/lib/install.sh"
# shellcheck source=lib/uninstall.sh
source "$SCRIPT_DIR/lib/uninstall.sh"
# shellcheck source=lib/help.sh
source "$SCRIPT_DIR/lib/help.sh"
# shellcheck source=lib/session.sh
source "$SCRIPT_DIR/lib/session.sh"
# shellcheck source=lib/api.sh
source "$SCRIPT_DIR/lib/api.sh"
# shellcheck source=lib/fallback.sh
source "$SCRIPT_DIR/lib/fallback.sh"
# shellcheck source=lib/safescan.sh
source "$SCRIPT_DIR/lib/safescan.sh"

cocoloop::print_json_or_raw() {
  local payload="${1:-}"
  if cocoloop::has_jq; then
    jq . <<<"$payload"
  else
    printf '%s\n' "$payload"
  fi
}

cocoloop::read_skill_version() {
  local skill_root="$1"
  cocoloop::trim_line_endings "$(sed -nE 's/^version:[[:space:]]*"?([^"]+)"?/\1/p' "${skill_root}/SKILL.md" | head -n 1)"
}

cocoloop::show_search_results() {
  local payload="$1"
  local count=""
  count="$(cocoloop::json_get '.data.items | length' "$payload" | head -n 1 || true)"

  if [[ -n "$count" && "$count" == "0" ]]; then
    return 1
  fi

  if cocoloop::has_jq; then
    jq -r '
      .data.items[]? |
      "[\(.id|tostring)] \(.name // .original_name // "-") | author=\((.author // "") | if . == "" then "-" else . end) | version=\((.version // .latest_version // "") | if . == "" then "-" else . end) | security=\((.security_level // .cls_certify // "") | if . == "" then "-" else . end) | download=\((.download_url // "") | if . == "" then "-" else . end)"
    ' <<<"$payload"
    return 0
  fi

  printf '%s\n' "$payload"
}

cocoloop::show_local_search_results() {
  local results_file="$1"
  local count=0
  local skill_name agent_name scope path

  [[ -f "$results_file" ]] || return 1

  while IFS=$'\t' read -r skill_name agent_name scope path; do
    [[ -n "$skill_name" ]] || continue
    count=$((count + 1))
    printf -- '- %s | agent=%s | scope=%s | path=%s\n' \
      "$skill_name" \
      "$agent_name" \
      "$scope" \
      "$path"
  done <"$results_file"

  [[ "$count" -gt 0 ]]
}

cocoloop::show_fallback_hints() {
  local query="$1"
  cocoloop::print_kv "FALLBACK_CLAWHUB" "$(cocoloop_fallback_clawhub_url "$query")"
  cocoloop::print_kv "FALLBACK_SKILLS_SH" "$(cocoloop_fallback_skills_sh_url "$query")"
  cocoloop::print_kv "FALLBACK_GITHUB" "$(cocoloop_fallback_github_search_url "$query")"
}

cocoloop::local_search_has_migration_candidates() {
  local results_file="$1"
  local current_agent="$2"
  local skill_name agent_name scope path

  [[ -f "$results_file" ]] || return 1

  while IFS=$'\t' read -r skill_name agent_name scope path; do
    [[ -n "$skill_name" ]] || continue
    if [[ "$agent_name" != "$current_agent" ]]; then
      return 0
    fi
  done <"$results_file"

  return 1
}

cocoloop::search::run_sources() {
  local query="$1"
  local official_file="$2"
  local local_file="$3"

  (
    cocoloop_api_search "$query" >"$official_file" || printf '{"data":{"items":[]}}\n' >"$official_file"
  ) &
  local official_pid=$!

  (
    cocoloop::platform::search_local_skills "$query" >"$local_file" || : >"$local_file"
  ) &
  local local_pid=$!

  wait "$official_pid"
  wait "$local_pid"
}

cocoloop::show_inspect_summary() {
  local payload="$1"
  if ! cocoloop::has_jq; then
    cocoloop::print_json_or_raw "$payload"
    return 0
  fi

  cocoloop::print_kv "ID" "$(cocoloop::json_get_first_nonempty "$payload" '.data.id' || true)"
  cocoloop::print_kv "NAME" "$(cocoloop::json_get_first_nonempty "$payload" '.data.name' '.data.original_name' || true)"
  cocoloop::print_kv "AUTHOR" "$(cocoloop::json_get_first_nonempty "$payload" '.data.author' || true)"
  cocoloop::print_kv "VERSION" "$(cocoloop::json_get_first_nonempty "$payload" '.data.version' '.data.latest_version' || true)"
  cocoloop::print_kv "SECURITY_LEVEL" "$(cocoloop::json_get_first_nonempty "$payload" '.data.security_level' '.data.cls_certify' || true)"
  cocoloop::print_kv "SOURCE_CREDIBILITY" "$(cocoloop::json_get_first_nonempty "$payload" '.data.source_credibility' || true)"
  cocoloop::print_kv "DOWNLOAD_URL" "$(cocoloop::json_get_first_nonempty "$payload" '.data.download_url' || true)"
  cocoloop::print_kv "BRIEF" "$(cocoloop::json_get_first_nonempty "$payload" '.data.brief' '.data.desc' || true)"
}

cocoloop::resolve_skill_id() {
  local target="$1"
  local item id

  if [[ "$target" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  item="$(cocoloop::resolve_exact_skill_item "$target" || true)"
  id="$(cocoloop::json_get '.id // empty' "$item" | head -n 1 || true)"
  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

cocoloop::command::inspect_not_found() {
  local target="$1"
  cocoloop::print_kv "COMMAND" "inspect"
  cocoloop::print_kv "STATUS" "not-found"
  cocoloop::print_kv "QUERY" "$target"
}

cocoloop::command::search() {
  local query="$1"
  local payload exact_item exact_name
  local search_dir official_file local_file
  local official_found=0 local_found=0 migration_found=0 current_agent

  search_dir="$(mktemp -d "${TMPDIR:-/tmp}/cocoloop-search.XXXXXX")"
  official_file="${search_dir}/official.json"
  local_file="${search_dir}/local.tsv"
  cocoloop::search::run_sources "$query" "$official_file" "$local_file"
  payload="$(cat "$official_file")"
  current_agent="$(cocoloop::platform::detect_agent)"
  cocoloop::print_kv "COMMAND" "search"
  cocoloop::print_kv "QUERY" "$query"

  printf 'OFFICIAL_RESULTS:\n'
  if cocoloop::show_search_results "$payload"; then
    official_found=1
  else
    printf '  - none\n'
  fi

  printf 'LOCAL_AGENT_RESULTS:\n'
  if cocoloop::show_local_search_results "$local_file"; then
    local_found=1
  else
    printf '  - none\n'
  fi

  if [[ "$official_found" -eq 0 && "$local_found" -eq 0 ]]; then
    cocoloop::print_kv "STATUS" "no-results"
    cocoloop::show_fallback_hints "$query"
    cocoloop::print_kv "NEXT_STEP" "agent-judgment-or-user-confirmation"
    rm -rf "$search_dir"
    return 0
  fi

  if [[ "$official_found" -eq 1 ]]; then
    exact_item="$(cocoloop::payload_exact_skill_item "$payload" "$query" || true)"
    if [[ -n "$exact_item" ]]; then
      exact_name="$(cocoloop::json_get '.name // .original_name // empty' "$exact_item" | head -n 1 || true)"
      cocoloop::print_kv "EXACT_MATCH" "yes"
      [[ -n "$exact_name" ]] && cocoloop::print_kv "EXACT_MATCH_SKILL" "$exact_name"
    else
      cocoloop::print_kv "EXACT_MATCH" "no"
    fi
  else
    cocoloop::print_kv "EXACT_MATCH" "no"
  fi

  if [[ "$local_found" -eq 1 ]]; then
    if cocoloop::local_search_has_migration_candidates "$local_file" "$current_agent"; then
      migration_found=1
    fi
  fi

  if [[ "$migration_found" -eq 1 ]]; then
    cocoloop::print_kv "LOCAL_MIGRATION_AVAILABLE" "yes"
    cocoloop::print_kv "LOCAL_NEXT_STEP" "ask-user-whether-to-migrate"
  elif [[ "$local_found" -eq 1 ]]; then
    cocoloop::print_kv "LOCAL_MIGRATION_AVAILABLE" "no"
    cocoloop::print_kv "LOCAL_NEXT_STEP" "local-skill-already-present"
  else
    cocoloop::print_kv "LOCAL_MIGRATION_AVAILABLE" "no"
  fi

  cocoloop::print_kv "STATUS" "review-required"
  cocoloop::print_kv "NEXT_STEP" "agent-judgment-or-user-confirmation"
  rm -rf "$search_dir"
}

cocoloop::command::inspect() {
  local target="$1"
  local skill_id payload

  if skill_id="$(cocoloop::resolve_skill_id "$target" 2>/dev/null)"; then
    payload="$(cocoloop_api_inspect_skill_by_id "$skill_id")"
  else
    cocoloop::command::inspect_not_found "$target"
    return 1
  fi

  cocoloop::show_inspect_summary "$payload"
}

cocoloop::command::update() {
  local target="$1"
  local normalized_target record path source source_type version scope installed_version latest_version payload official_id
  local latest_download search_payload matched_item update_source install_output refresh_record refreshed_path refreshed_version refreshed_scope
  normalized_target="$(cocoloop::normalize_name "$target")"
  record="$(cocoloop_session_find_install "$normalized_target" 2>/dev/null || true)"
  [[ -n "$record" ]] || cocoloop::die "not_installed" "未找到已安装记录: $target"

  IFS=$'\t' read -r _ path source source_type version scope _ official_id <<<"$record"
  installed_version="${version:-unknown}"
  update_source="$source"

  if [[ "$source_type" == "official" ]]; then
    if [[ -n "$official_id" ]]; then
      payload="$(cocoloop_api_inspect_skill_by_id "$official_id" 2>/dev/null || true)"
      latest_version="$(cocoloop::json_get_first_nonempty "$payload" '.data.version' '.data.latest_version' || true)"
      latest_download="$(cocoloop::json_get_first_nonempty "$payload" '.data.download_url' || true)"

      search_payload="$(cocoloop_api_search "$target" 2>/dev/null || true)"
      if [[ -n "$search_payload" ]] && cocoloop::has_jq; then
        matched_item="$(jq -c --arg id "$official_id" '.data.items[]? | select((.id | tostring) == $id)' <<<"$search_payload" | head -n 1 || true)"
        if [[ -n "$matched_item" && "$matched_item" != "null" ]]; then
          [[ -n "$latest_version" ]] || latest_version="$(cocoloop::json_get '.version // .latest_version // empty' "$matched_item" | head -n 1 || true)"
          [[ -n "$latest_download" ]] || latest_download="$(cocoloop::json_get '.download_url // empty' "$matched_item" | head -n 1 || true)"
        fi
      fi
    else
      payload="$(cocoloop_api_search "$target")"
      latest_version="$(cocoloop::json_get '.data.items[0].version // empty' "$payload" | head -n 1 || true)"
      latest_download="$(cocoloop::json_get '.data.items[0].download_url // empty' "$payload" | head -n 1 || true)"
    fi
    [[ -n "$latest_download" ]] && update_source="$latest_download"
  elif [[ -f "${path}/SKILL.md" ]]; then
    latest_version="$(cocoloop::read_skill_version "$path")"
  fi

  if [[ -n "$latest_version" && "$latest_version" == "$installed_version" ]]; then
    cocoloop::print_kv "COMMAND" "update"
    cocoloop::print_kv "STATUS" "up-to-date"
    cocoloop::print_kv "TARGET" "$target"
    cocoloop::print_kv "VERSION" "$installed_version"
    return 0
  fi

  cocoloop::print_kv "COMMAND" "update"
  cocoloop::print_kv "STATUS" "updating"
  cocoloop::print_kv "TARGET" "$target"
  cocoloop::print_kv "CURRENT_VERSION" "$installed_version"
  [[ -n "$latest_version" ]] && cocoloop::print_kv "LATEST_VERSION" "$latest_version"
  [[ -n "$official_id" ]] && cocoloop::print_kv "OFFICIAL_ID" "$official_id"
  install_output="$(cocoloop::install::plan "$update_source" "$scope" "true")"
  printf '%s\n' "$install_output"

  if [[ "$source_type" == "official" && -n "$official_id" && "$install_output" == *"STATUS: installed"* ]]; then
    refresh_record="$(cocoloop_session_find_install "$normalized_target" 2>/dev/null || true)"
    if [[ -n "$refresh_record" ]]; then
      IFS=$'\t' read -r _ refreshed_path _ _ refreshed_version refreshed_scope _ _ <<<"$refresh_record"
      cocoloop_session_record_install \
        "$normalized_target" \
        "${refreshed_path:-$path}" \
        "$update_source" \
        "official" \
        "${refreshed_version:-$latest_version}" \
        "${refreshed_scope:-$scope}" \
        "$official_id"
    fi
  fi
}

cocoloop::command::update_self() {
  local current_version
  current_version="$(sed -nE 's/^version:[[:space:]]*([0-9.]+).*/\1/p' "$SCRIPT_DIR/../SKILL.md" | head -n 1)"
  cocoloop::print_json_or_raw "$(cocoloop_api_check_upgrade "${current_version:-0.0.0}" "$(cocoloop::platform::detect_os)")"
}

cocoloop::command::like() {
  local skill_name="$1"
  local payload
  payload="$(cocoloop_api_like "$skill_name" 2>/dev/null || true)"
  cocoloop_session_add_like "$skill_name"
  cocoloop::print_kv "COMMAND" "like"
  cocoloop::print_kv "SKILL" "$skill_name"
  cocoloop::print_kv "STATUS" "recorded"
  [[ -n "$payload" ]] && cocoloop::print_json_or_raw "$payload"
}

cocoloop::command::like_list() {
  local payload local_like normalized record path count

  payload="$(cocoloop_api_like_list 2>/dev/null || true)"
  if [[ -n "$payload" && "$payload" != "null" ]] && cocoloop::has_jq && [[ "$(jq -r '.code // 0' <<<"$payload" 2>/dev/null)" == "0" ]]; then
    cocoloop::print_kv "COMMAND" "like-list"
    cocoloop::print_kv "STATUS" "remote"
    cocoloop::print_json_or_raw "$payload"
    return 0
  fi

  cocoloop::print_kv "COMMAND" "like-list"
  count=0
  while IFS= read -r local_like; do
    [[ -n "$local_like" ]] || continue
    count=$((count + 1))
    normalized="$(cocoloop::normalize_name "$local_like")"
    record="$(cocoloop_session_find_install "$normalized" 2>/dev/null || true)"
    path=""
    if [[ -n "$record" ]]; then
      IFS=$'\t' read -r _ path _ <<<"$record"
    fi
    printf -- '- %s | installed=%s | path=%s\n' \
      "$local_like" \
      "$( [[ -n "$path" ]] && printf yes || printf no )" \
      "${path:--}"
  done < <(cocoloop_session_list_likes)

  if [[ "$count" -eq 0 ]]; then
    cocoloop::print_kv "STATUS" "empty"
    cocoloop::print_kv "LIKES_COUNT" "0"
    return 0
  fi

  cocoloop::print_kv "STATUS" "local"
  cocoloop::print_kv "LIKES_COUNT" "$count"
}

cocoloop::command::candidate_json() {
  local payload="$1"
  cocoloop::print_json_or_raw "$(cocoloop_api_candidate "$payload")"
}

cocoloop::command::candidate_file() {
  local file_path="$1"
  cocoloop::require_file "$file_path"
  cocoloop::print_json_or_raw "$(cocoloop_api_candidate "$(cat "$file_path")")"
}

cocoloop::command::healthcheck() {
  local ping health
  ping="$(cocoloop_api_ping)"
  health="$(cocoloop_api_healthcheck)"
  cocoloop::print_kv "PING" "$(cocoloop::json_get_first_nonempty "$ping" '.message' '.data' || printf '%s' "$ping")"
  cocoloop::print_json_or_raw "$health"
}

cocoloop::command::paths() {
  local agent_name="$1"
  local os_platform="$2"
  local remote

  cocoloop::platform::describe_paths "$agent_name" "$os_platform"
  remote="$(cocoloop_api_agent_skill_paths "$agent_name" "$os_platform" 2>/dev/null || true)"
  if [[ -n "$remote" ]]; then
    printf 'REMOTE_PATHS:\n'
    if cocoloop::has_jq; then
      jq -r '
        .data.items[]?
        | { path: (.path // "-"), status: (.status // "unknown") }
        | "\(.path)\t\(.status)"
      ' <<<"$remote" | awk -F '\t' '!seen[$0]++ { printf "  - %s (%s)\n", $1, $2 }'
    else
      printf '%s\n' "$remote"
    fi
  fi
}

cocoloop::command::safescan() {
  local target="$1"
  if [[ -f "$target" ]]; then
    cocoloop_safescan_upload_file "$target"
  elif [[ -d "$target" ]]; then
    cocoloop_safescan_upload_directory "$target"
  else
    cocoloop_safescan_report "$target"
  fi
}

cocoloop::parse_query_command() {
  local command="$1"
  shift
  local query=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query)
        query="${2:-}"
        shift 2
        ;;
      -h|--help)
        cocoloop::help::subcommand "$command"
        return 0
        ;;
      *)
        cocoloop::die "invalid_argument" "$command 仅支持 --query QUERY。"
        ;;
    esac
  done

  [[ -n "$query" ]] || cocoloop::die "missing_argument" "$command 需要 --query QUERY。"
  case "$command" in
    search) cocoloop::command::search "$query" ;;
    *) cocoloop::die "unknown_command" "未实现的查询命令: $command" ;;
  esac
}

cocoloop::parse_single_arg_command() {
  local command="$1"
  shift

  case "${1:-}" in
    -h|--help)
      cocoloop::help::subcommand "$command"
      return 0
      ;;
    '')
      cocoloop::die "missing_argument" "$command 需要一个目标参数。"
      ;;
  esac

  [[ $# -eq 1 ]] || cocoloop::die "invalid_argument" "$command 只接受一个目标参数。"
  case "$command" in
    inspect) cocoloop::command::inspect "$1" ;;
    update) cocoloop::command::update "$1" ;;
    safescan) cocoloop::command::safescan "$1" ;;
    *) cocoloop::die "unknown_command" "未实现的目标命令: $command" ;;
  esac
}

cocoloop::parse_install() {
  local source_arg=""
  local scope="auto"
  local force="false"
  local selected_skills=""
  local install_all="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope)
        scope="${2:-}"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      --skills)
        selected_skills="${2:-}"
        shift 2
        ;;
      --all)
        install_all="true"
        shift
        ;;
      -h|--help)
        cocoloop::help::subcommand install
        return 0
        ;;
      --*)
        cocoloop::die "invalid_argument" "install 不支持参数: $1"
        ;;
      *)
        [[ -z "$source_arg" ]] || cocoloop::die "invalid_argument" "install 只接受一个来源参数。"
        source_arg="$1"
        shift
        ;;
    esac
  done

  [[ -n "$source_arg" ]] || cocoloop::die "missing_argument" "install 需要技能名、URL、仓库地址或本地路径。"
  if [[ "$install_all" == "true" && -n "$selected_skills" ]]; then
    cocoloop::die "invalid_argument" "install 不能同时使用 --all 和 --skills。"
  fi
  cocoloop::install::plan "$source_arg" "$scope" "$force" "$selected_skills" "$install_all"
}

cocoloop::parse_uninstall() {
  local skill_name=""
  local scope="all"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope)
        scope="${2:-}"
        shift 2
        ;;
      -h|--help)
        cocoloop::help::subcommand uninstall
        return 0
        ;;
      --*)
        cocoloop::die "invalid_argument" "uninstall 不支持参数: $1"
        ;;
      *)
        [[ -z "$skill_name" ]] || cocoloop::die "invalid_argument" "uninstall 只接受一个技能名。"
        skill_name="$1"
        shift
        ;;
    esac
  done

  [[ -n "$skill_name" ]] || cocoloop::die "missing_argument" "uninstall 需要一个技能名。"
  cocoloop::uninstall::plan "$skill_name" "$scope"
}

cocoloop::parse_like() {
  local skill_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skill)
        skill_name="${2:-}"
        shift 2
        ;;
      -h|--help)
        cocoloop::help::subcommand like
        return 0
        ;;
      *)
        cocoloop::die "invalid_argument" "like 仅支持 --skill SKILL。"
        ;;
    esac
  done

  [[ -n "$skill_name" ]] || cocoloop::die "missing_argument" "like 需要 --skill SKILL。"
  cocoloop::command::like "$skill_name"
}

cocoloop::parse_candidate() {
  local data_json=""
  local data_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data-json)
        data_json="${2:-}"
        shift 2
        ;;
      --data-file)
        data_file="${2:-}"
        shift 2
        ;;
      -h|--help)
        cocoloop::help::subcommand candidate
        return 0
        ;;
      *)
        cocoloop::die "invalid_argument" "candidate 仅支持 --data-json 或 --data-file。"
        ;;
    esac
  done

  if [[ -n "$data_json" && -n "$data_file" ]]; then
    cocoloop::die "invalid_argument" "candidate 不能同时传 --data-json 和 --data-file。"
  fi
  if [[ -z "$data_json" && -z "$data_file" ]]; then
    cocoloop::die "missing_argument" "candidate 至少需要 --data-json 或 --data-file。"
  fi

  if [[ -n "$data_file" ]]; then
    cocoloop::command::candidate_file "$data_file"
  else
    cocoloop::command::candidate_json "$data_json"
  fi
}

cocoloop::parse_paths() {
  local agent_name=""
  local os_platform=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        agent_name="${2:-}"
        shift 2
        ;;
      --os)
        os_platform="${2:-}"
        shift 2
        ;;
      -h|--help)
        cocoloop::help::subcommand paths
        return 0
        ;;
      *)
        cocoloop::die "invalid_argument" "paths 仅支持 --agent 和 --os。"
        ;;
    esac
  done

  [[ -n "$agent_name" ]] || agent_name="$(cocoloop::platform::detect_agent)"
  [[ -n "$os_platform" ]] || os_platform="$(cocoloop::platform::detect_os)"
  cocoloop::command::paths "$agent_name" "$os_platform"
}

cocoloop::main() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    help|-h|--help)
      cocoloop::help::main
      ;;
    search)
      cocoloop::parse_query_command search "$@"
      ;;
    inspect)
      cocoloop::parse_single_arg_command inspect "$@"
      ;;
    install)
      cocoloop::parse_install "$@"
      ;;
    uninstall)
      cocoloop::parse_uninstall "$@"
      ;;
    update)
      cocoloop::parse_single_arg_command update "$@"
      ;;
    update-self)
      if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
        cocoloop::help::subcommand update-self
      else
        cocoloop::command::update_self
      fi
      ;;
    like)
      cocoloop::parse_like "$@"
      ;;
    like-list)
      if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
        cocoloop::help::subcommand like-list
      else
        cocoloop::command::like_list
      fi
      ;;
    candidate)
      cocoloop::parse_candidate "$@"
      ;;
    healthcheck)
      if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
        cocoloop::help::subcommand healthcheck
      else
        cocoloop::command::healthcheck
      fi
      ;;
    paths)
      cocoloop::parse_paths "$@"
      ;;
    safescan)
      cocoloop::parse_single_arg_command safescan "$@"
      ;;
    *)
      cocoloop::die "unknown_command" "未知命令: $command。运行 'cocoloop --help' 查看可用命令。"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cocoloop::main "$@"
fi
