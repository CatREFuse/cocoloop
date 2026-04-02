#!/usr/bin/env bash

cocoloop::install::temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/cocoloop-install.XXXXXX"
}

cocoloop::install::cleanup_work_dir() {
  local work_dir="${1:-}"
  [[ -n "$work_dir" ]] || return 0
  [[ -d "$work_dir" ]] || return 0
  [[ "${COCOLOOP_KEEP_TMP:-0}" == "1" ]] && return 0
  rm -rf "$work_dir"
}

cocoloop::install::last_error_file() {
  printf '%s/install-last-error.log\n' "$(cocoloop_logs_dir)"
}

cocoloop::install::infer_type() {
  local input="$1"
  if [[ -d "$input" || -f "$input" ]]; then
    printf 'local'
  elif [[ "$input" =~ ^https?:// ]]; then
    printf 'url'
  elif [[ "$input" =~ ^[^/]+/[^/]+$ || "$input" =~ ^https://github.com/ ]]; then
    printf 'github'
  else
    printf 'skill-name'
  fi
}

cocoloop::install::version_from_root() {
  local skill_root="$1"
  cocoloop::trim_line_endings "$(sed -nE 's/^version:[[:space:]]*"?([^"]+)"?/\1/p' "${skill_root}/SKILL.md" | head -n 1)"
}

cocoloop::install::find_skill_root() {
  local input="$1"

  if [[ -f "$input" ]]; then
    cocoloop::die "unsupported_source" "当前版本暂不支持直接从单文件安装: $input"
  fi

  if [[ -f "$input/SKILL.md" ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  local nested
  nested="$(find "$input" -type f -name SKILL.md -print -quit 2>/dev/null || true)"
  [[ -n "$nested" ]] || cocoloop::die "invalid_skill" "在来源目录中没有找到 SKILL.md: $input"
  dirname "$nested"
}

cocoloop::install::find_skill_roots() {
  local input="$1"
  local nested=""

  if [[ -f "$input" ]]; then
    cocoloop::die "unsupported_source" "当前版本暂不支持直接从单文件安装: $input"
  fi

  if [[ -f "$input/SKILL.md" ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  while IFS= read -r nested; do
    [[ -n "$nested" ]] || continue
    dirname "$nested"
  done < <(find "$input" -type f -name SKILL.md 2>/dev/null || true) | awk 'NF && !seen[$0]++'
}

cocoloop::install::skill_name_from_root() {
  cocoloop::skill_name_from_root "$1"
}

cocoloop::install::target_path() {
  local skill_name="$1"
  local scope="$2"
  local agent_name="$3"
  printf '%s/%s' "$(cocoloop::platform::resolve_target_root "$scope" "$agent_name")" "$skill_name"
}

cocoloop::install::store_path() {
  local skill_name="$1"
  printf '%s/%s' "$(cocoloop_skills_store_dir)" "$skill_name"
}

cocoloop::install::required_tools() {
  local source_type="$1"
  printf 'cp\nfind\n'
  case "$source_type" in
    local)
      printf ''
      ;;
    url|official|github|skill-name)
      printf 'curl\n'
      printf 'file\n'
      printf 'unzip\n'
      ;;
  esac
  case "$source_type" in
    github|skill-name)
      printf 'jq\n'
      ;;
  esac
}

cocoloop::install::missing_tools() {
  local source_type="$1"
  local tool missing=0

  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf '%s\n' "$tool"
      missing=1
    fi
  done < <(cocoloop::install::required_tools "$source_type")

  return "$missing"
}

cocoloop::install::batch_support_reason() {
  local source_type="$1"
  local agent_name="$2"
  local missing_tools=""

  if ! cocoloop::platform::supports_batch_install "$agent_name"; then
    printf 'unsupported-environment\n'
    return 0
  fi

  missing_tools="$(cocoloop::install::missing_tools "$source_type" || true)"
  if [[ -n "$missing_tools" ]]; then
    printf 'missing-tools\n'
    return 0
  fi

  printf 'batch-supported\n'
}

cocoloop::install::handoff() {
  local source_arg="$1"
  local scope="$2"
  local force="$3"
  local input_type="$4"
  local agent_name="$5"
  local reason="$6"
  local detail="${7:-}"
  local target_path=""

  if [[ "$input_type" == "skill-name" ]] && cocoloop::platform::supports_batch_install "$agent_name"; then
    target_path="$(cocoloop::install::target_path "$(cocoloop::normalize_name "$source_arg")" "$scope" "$agent_name" 2>/dev/null || true)"
  fi
  cocoloop::print_kv "COMMAND" "install"
  cocoloop::print_kv "STATUS" "handoff-to-agent"
  cocoloop::print_kv "INPUT_TYPE" "$input_type"
  cocoloop::print_kv "AGENT" "$agent_name"
  [[ -n "$target_path" ]] && cocoloop::print_kv "TARGET_PATH" "$target_path"
  cocoloop::print_kv "FORCE" "$force"
  cocoloop::print_kv "REASON" "$reason"
  cocoloop::print_kv "NEXT_STEP" "agent-exploration"
  [[ -n "$detail" ]] && cocoloop::print_kv "DETAIL" "$detail"
  return 0
}

cocoloop::install::supports_symlink_publish() {
  local os_platform
  os_platform="$(cocoloop::platform::detect_os)"
  [[ "$os_platform" != "windows" ]] || return 1
  command -v ln >/dev/null 2>&1
}

cocoloop::install::verify() {
  local source_root="$1"
  local target_path="$2"
  local dir_name

  [[ -f "${target_path}/SKILL.md" ]] || cocoloop::die "install_verify_failed" "安装后缺少 SKILL.md: ${target_path}"

  for dir_name in scripts references assets agents; do
    if [[ -d "${source_root}/${dir_name}" && ! -d "${target_path}/${dir_name}" ]]; then
      cocoloop::die "install_verify_failed" "安装后缺少目录 ${dir_name}: ${target_path}"
    fi
  done
}

cocoloop::install::copy_skill_root() {
  local source_root="$1"
  local target_path="$2"
  local force="$3"
  local publish_mode="${4:-copy}"
  local target_root

  target_root="$(dirname "$target_path")"
  cocoloop::ensure_dir "$target_root"

  if [[ -e "$target_path" ]]; then
    if [[ "$force" != "true" ]]; then
      cocoloop::die "target_exists" "目标路径已存在。可加 --force 覆盖: $target_path"
    fi
    rm -rf "$target_path"
  fi

  case "$publish_mode" in
    symlink)
      ln -s "$source_root" "$target_path"
      ;;
    copy)
      cp -R "$source_root" "$target_path"
      ;;
    *)
      cocoloop::die "invalid_publish_mode" "未知安装发布方式: $publish_mode"
      ;;
  esac

  cocoloop::install::verify "$source_root" "$target_path"
}

cocoloop::install::stage_skill_root() {
  local source_root="$1"
  local store_path="$2"
  local force="$3"

  cocoloop::ensure_dir "$(dirname "$store_path")"

  if [[ -e "$store_path" ]]; then
    if [[ "$force" != "true" ]]; then
      cocoloop::die "target_exists" "Cocoloop 技能仓库已存在该 Skill。可加 --force 覆盖: $store_path"
    fi
    rm -rf "$store_path"
  fi

  cp -R "$source_root" "$store_path"
  cocoloop::install::verify "$source_root" "$store_path"
}

cocoloop::install::download_file() {
  local url="$1"
  local destination="$2"
  curl --silent --show-error --location --max-time "${COCOLOOP_DOWNLOAD_TIMEOUT:-60}" -o "$destination" "$url"
}

cocoloop::install::extract_archive() {
  local archive="$1"
  local output_dir="$2"

  case "$archive" in
    *.zip)
      unzip -q "$archive" -d "$output_dir"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$output_dir"
      ;;
    *.tar)
      tar -xf "$archive" -C "$output_dir"
      ;;
    *)
      cocoloop::die "unsupported_archive" "不支持的压缩格式: $archive"
      ;;
  esac
}

cocoloop::install::prepare_from_url() {
  local url="$1"
  local work_dir="$2"

  if [[ "$url" =~ github\.com/ ]]; then
    cocoloop::install::prepare_from_github "$url" "$work_dir"
    return 0
  fi

  local filename downloaded extracted_dir
  filename="$(basename "${url%%\?*}")"
  [[ -n "$filename" ]] || filename="download.bin"
  downloaded="${work_dir}/${filename}"
  cocoloop::install::download_file "$url" "$downloaded"

  if file "$downloaded" | grep -qi 'HTML'; then
    cocoloop::die "unsupported_source_page" "当前 URL 指向页面而不是已知可安装归档，请交给 Agent 探索安装: $url"
  fi

  extracted_dir="${work_dir}/extracted"
  cocoloop::ensure_dir "$extracted_dir"
  cocoloop::install::extract_archive "$downloaded" "$extracted_dir"
  printf '%s\n' "$extracted_dir"
}

cocoloop::install::prepare_from_github() {
  local source="$1"
  local work_dir="$2"
  local repo_path owner repo branch subpath api_payload archive_url archive_path extracted_dir

  repo_path="$source"
  repo_path="${repo_path#https://github.com/}"
  repo_path="${repo_path#github.com/}"
  repo_path="${repo_path%%\?*}"
  repo_path="${repo_path%%#*}"

  if [[ "$repo_path" =~ ^([^/]+)/([^/]+)(/tree/([^/]+)(/(.+))?)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    branch="${BASH_REMATCH[4]:-}"
    subpath="${BASH_REMATCH[6]:-}"
  elif [[ "$repo_path" =~ ^([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    branch=""
    subpath=""
  else
    cocoloop::die "invalid_github_source" "无法解析 GitHub 来源: $source"
  fi

  if [[ -n "$subpath" ]]; then
    cocoloop::die "unsupported_github_subpath" "当前版本不在 install 中解析 GitHub 子目录，请交给 Agent 探索安装: $source"
  fi

  repo="${repo%.git}"
  if [[ -z "$branch" ]]; then
    api_payload="$(curl --silent --show-error --location "https://api.github.com/repos/${owner}/${repo}")"
    branch="$(cocoloop::json_get '.default_branch // empty' "$api_payload" | head -n 1)"
    [[ -n "$branch" ]] || branch="main"
  fi

  archive_url="https://codeload.github.com/${owner}/${repo}/zip/refs/heads/${branch}"
  archive_path="${work_dir}/${repo}-${branch}.zip"
  cocoloop::install::download_file "$archive_url" "$archive_path"

  extracted_dir="${work_dir}/extracted"
  cocoloop::ensure_dir "$extracted_dir"
  cocoloop::install::extract_archive "$archive_path" "$extracted_dir"
  printf '%s\n' "$extracted_dir"
}

cocoloop::install::selection_values() {
  local raw="$1"
  printf '%s' "$raw" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '-' \
    | awk 'NF && !seen[$0]++'
}

cocoloop::install::emit_multi_skill_review() {
  local reason="$1"
  local source_arg="$2"
  shift 2
  local root skill_name

  printf 'REVIEW_REQUIRED: %s\n' "$reason"
  printf 'SOURCE: %s\n' "$source_arg"
  for root in "$@"; do
    [[ -n "$root" ]] || continue
    skill_name="$(cocoloop::install::skill_name_from_root "$root")"
    printf 'CANDIDATE: %s\t%s\n' "$skill_name" "$root"
  done
  printf 'SELECTION_HINT: rerun with --skills skill-a,skill-b or --all\n'
}

cocoloop::install::emit_official_review() {
  local query="$1"
  local payload="$2"

  printf 'REVIEW_REQUIRED: official-search-results\n'
  printf 'QUERY: %s\n' "$query"
  if cocoloop::has_jq; then
    jq -r '
      .data.items[]? |
      "CANDIDATE: \((.name // .original_name // "-"))\t\((.id // "-")|tostring)\t\((.download_url // "-"))"
    ' <<<"$payload"
  fi
  printf 'SELECTION_HINT: rerun install with an exact skill name after user or Agent confirmation\n'
}

cocoloop::install::selected_roots() {
  local source_arg="$1"
  local container_root="$2"
  local selection="${3:-}"
  local install_all="${4:-false}"
  local review_reason="${5:-multi-skill-source}"
  local root skill_name requested_list=""
  local -a roots=()
  local matched=0

  while IFS= read -r root; do
    [[ -n "$root" ]] || continue
    roots+=("$root")
  done < <(cocoloop::install::find_skill_roots "$container_root")

  [[ ${#roots[@]} -gt 0 ]] || cocoloop::die "invalid_skill" "在来源目录中没有找到 SKILL.md: $container_root"

  if [[ ${#roots[@]} -eq 1 ]]; then
    printf '%s\n' "${roots[0]}"
    return 0
  fi

  if [[ "$install_all" == "true" ]]; then
    printf '%s\n' "${roots[@]}"
    return 0
  fi

  if [[ -n "$selection" ]]; then
    requested_list="$(cocoloop::install::selection_values "$selection" || true)"

    for root in "${roots[@]}"; do
      skill_name="$(cocoloop::install::skill_name_from_root "$root")"
      if [[ -n "$requested_list" ]] && grep -Fxq "$skill_name" <<<"$requested_list"; then
        printf '%s\n' "$root"
        matched=1
      fi
    done

    if [[ $matched -eq 1 ]]; then
      return 0
    fi

    cocoloop::install::emit_multi_skill_review "$review_reason" "$source_arg" "${roots[@]}"
    printf 'SELECTION_ERROR: 未找到指定的 Skill 选择: %s\n' "$selection"
    return 10
  fi

  cocoloop::install::emit_multi_skill_review "$review_reason" "$source_arg" "${roots[@]}"
  return 10
}

cocoloop::install::record_success() {
  local skill_name="$1"
  local target_path="$2"
  local source="$3"
  local source_type="$4"
  local version="$5"
  local scope="$6"
  local official_id="${7:-}"

  cocoloop_session_record_install "$skill_name" "$target_path" "$source" "$source_type" "${version:-unknown}" "$scope" "$official_id"
}

cocoloop::install::perform_from_root() {
  local source_root="$1"
  local source_arg="$2"
  local source_type="$3"
  local scope="$4"
  local force="$5"
  local official_id="${6:-}"
  local agent_name skill_name store_path target_path version install_strategy

  agent_name="$(cocoloop::platform::detect_agent)"
  skill_name="$(cocoloop::install::skill_name_from_root "$source_root")"
  store_path="$(cocoloop::install::store_path "$skill_name")"
  target_path="$(cocoloop::install::target_path "$skill_name" "$scope" "$agent_name")"
  version="$(cocoloop::install::version_from_root "$source_root")"

  cocoloop::install::stage_skill_root "$source_root" "$store_path" "$force"
  install_strategy="copy"
  if cocoloop::install::supports_symlink_publish; then
    cocoloop::install::copy_skill_root "$store_path" "$target_path" "$force" "symlink"
    install_strategy="symlink"
  else
    cocoloop::install::copy_skill_root "$store_path" "$target_path" "$force" "copy"
  fi
  cocoloop::install::record_success "$skill_name" "$target_path" "$source_arg" "$source_type" "$version" "$scope" "$official_id"

  cocoloop::print_kv "COMMAND" "install"
  cocoloop::print_kv "STATUS" "installed"
  cocoloop::print_kv "INPUT_TYPE" "$source_type"
  cocoloop::print_kv "AGENT" "$agent_name"
  cocoloop::print_kv "SKILL" "$skill_name"
  cocoloop::print_kv "VERSION" "${version:-unknown}"
  cocoloop::print_kv "SOURCE_ROOT" "$source_root"
  cocoloop::print_kv "STORE_PATH" "$store_path"
  cocoloop::print_kv "TARGET_PATH" "$target_path"
  [[ -n "$official_id" ]] && cocoloop::print_kv "OFFICIAL_ID" "$official_id"
  cocoloop::print_kv "INSTALL_STRATEGY" "$install_strategy"
  cocoloop::print_kv "NEXT_STEP" "user-test"
}

cocoloop::install::official_selected_item() {
  local query="$1"
  cocoloop::resolve_exact_skill_item "$query"
}

cocoloop::install::batch_execute() {
  local source_arg="$1"
  local scope="$2"
  local force="$3"
  local input_type="$4"
  local selected_skills="${5:-}"
  local install_all="${6:-false}"
  local selected_item download_url official_id official_name source_root work_dir payload container_root roots_output selection_status
  local -a source_roots=()

  case "$input_type" in
    local)
      if roots_output="$(cocoloop::install::selected_roots "$source_arg" "$source_arg" "$selected_skills" "$install_all" "multi-skill-source" 2>&1)"; then
        selection_status=0
      else
        selection_status=$?
      fi
      if [[ $selection_status -ne 0 ]]; then
        printf '%s\n' "$roots_output"
        return "$selection_status"
      fi
      while IFS= read -r source_root; do
        [[ -n "$source_root" ]] || continue
        source_roots+=("$source_root")
      done <<<"$roots_output"
      for source_root in "${source_roots[@]}"; do
        cocoloop::install::perform_from_root "$source_root" "$source_arg" "$input_type" "$scope" "$force"
      done
      ;;
    url)
      work_dir="$(cocoloop::install::temp_dir)"
      container_root="$(cocoloop::install::prepare_from_url "$source_arg" "$work_dir")" || {
        local prepare_status=$?
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$prepare_status"
      }
      if roots_output="$(cocoloop::install::selected_roots "$source_arg" "$container_root" "$selected_skills" "$install_all" "multi-skill-source" 2>&1)"; then
        selection_status=0
      else
        selection_status=$?
      fi
      if [[ $selection_status -ne 0 ]]; then
        printf '%s\n' "$roots_output"
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$selection_status"
      fi
      while IFS= read -r source_root; do
        [[ -n "$source_root" ]] || continue
        source_roots+=("$source_root")
      done <<<"$roots_output"
      for source_root in "${source_roots[@]}"; do
        if cocoloop::install::perform_from_root "$source_root" "$source_arg" "$input_type" "$scope" "$force"; then
          :
        else
          local perform_status=$?
          cocoloop::install::cleanup_work_dir "$work_dir"
          return "$perform_status"
        fi
      done
      cocoloop::install::cleanup_work_dir "$work_dir"
      ;;
    github)
      work_dir="$(cocoloop::install::temp_dir)"
      container_root="$(cocoloop::install::prepare_from_github "$source_arg" "$work_dir")" || {
        local prepare_status=$?
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$prepare_status"
      }
      if roots_output="$(cocoloop::install::selected_roots "$source_arg" "$container_root" "$selected_skills" "$install_all" "multi-skill-repo" 2>&1)"; then
        selection_status=0
      else
        selection_status=$?
      fi
      if [[ $selection_status -ne 0 ]]; then
        printf '%s\n' "$roots_output"
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$selection_status"
      fi
      while IFS= read -r source_root; do
        [[ -n "$source_root" ]] || continue
        source_roots+=("$source_root")
      done <<<"$roots_output"
      for source_root in "${source_roots[@]}"; do
        if cocoloop::install::perform_from_root "$source_root" "$source_arg" "$input_type" "$scope" "$force"; then
          :
        else
          local perform_status=$?
          cocoloop::install::cleanup_work_dir "$work_dir"
          return "$perform_status"
        fi
      done
      cocoloop::install::cleanup_work_dir "$work_dir"
      ;;
    skill-name)
      selected_item="$(cocoloop::install::official_selected_item "$source_arg" || true)"
      if [[ -z "$selected_item" ]]; then
        payload="$(cocoloop_api_search "$source_arg")"
        if [[ "$(cocoloop::json_get '.data.items | length' "$payload" | head -n 1 || true)" != "0" ]]; then
          cocoloop::install::emit_official_review "$source_arg" "$payload"
          return 10
        fi
        return 2
      fi
      download_url="$(cocoloop::json_get '.download_url // empty' "$selected_item" | head -n 1)"
      official_id="$(cocoloop::json_get '.id // empty' "$selected_item" | head -n 1)"
      official_name="$(cocoloop::json_get '.name // .original_name // empty' "$selected_item" | head -n 1)"
      [[ -n "$download_url" ]] || return 2
      work_dir="$(cocoloop::install::temp_dir)"
      container_root="$(cocoloop::install::prepare_from_url "$download_url" "$work_dir")" || {
        local prepare_status=$?
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$prepare_status"
      }
      if roots_output="$(cocoloop::install::selected_roots "$official_name" "$container_root" "$selected_skills" "$install_all" "multi-skill-source" 2>&1)"; then
        selection_status=0
      else
        selection_status=$?
      fi
      if [[ $selection_status -ne 0 ]]; then
        printf '%s\n' "$roots_output"
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$selection_status"
      fi
      source_root="$(printf '%s\n' "$roots_output" | head -n 1)"
      if cocoloop::install::perform_from_root "$source_root" "$download_url" "official" "$scope" "$force" "$official_id"; then
        :
      else
        local perform_status=$?
        cocoloop::install::cleanup_work_dir "$work_dir"
        return "$perform_status"
      fi
      [[ -n "$official_id" ]] && cocoloop_api_behavior_report "$official_id" download skill >/dev/null 2>&1 || true
      [[ -n "$official_name" ]] && cocoloop::print_kv "OFFICIAL_NAME" "$official_name"
      cocoloop::install::cleanup_work_dir "$work_dir"
      ;;
    *)
      return 3
      ;;
  esac
}

cocoloop::install::run_batch() {
  local source_arg="$1"
  local scope="$2"
  local force="$3"
  local input_type="$4"
  local log_file output status

  cocoloop_session_init_dirs
  log_file="$(cocoloop::install::last_error_file)"
  output="$(
    cocoloop::install::batch_execute "$source_arg" "$scope" "$force" "$input_type" "${5:-}" "${6:-false}" 2>&1
  )"
  status=$?
  : >"$log_file"
  [[ -n "$output" ]] && printf '%s\n' "$output" >"$log_file"
  if [[ $status -eq 0 ]]; then
    printf '%s\n' "$output"
    return 0
  fi
  return "$status"
}

cocoloop::install::classify_batch_failure() {
  local source_arg="$1"
  local input_type="$2"
  local log_file detail

  log_file="$(cocoloop::install::last_error_file)"
  detail="$(cat "$log_file" 2>/dev/null || true)"

  if [[ "$input_type" == "skill-name" ]] && [[ -z "$detail" ]]; then
    printf 'ambiguous-source\n'
    return 0
  fi

  if [[ "$detail" == REVIEW_REQUIRED:* ]]; then
    printf 'review-required\n'
    return 0
  fi

  case "$detail" in
    *"install_verify_failed"*) printf 'post-install-verification-failed\n' ;;
    *"unsupported_archive"*|*"unsupported_source_page"*|*"unsupported_github_subpath"*|*"unresolvable_page"*|*"invalid_github_source"*) printf 'installer-behavior-changed\n' ;;
    *) printf 'batch-install-failed\n' ;;
  esac
}

cocoloop::install::print_review_from_log() {
  local source_arg="$1"
  local scope="$2"
  local force="$3"
  local input_type="$4"
  local agent_name="$5"
  local log_file reason_line reason query_line source_line hint_line
  local candidate_line candidate_name candidate_meta candidate_path selection_error

  log_file="$(cocoloop::install::last_error_file)"
  reason_line="$(grep '^REVIEW_REQUIRED:' "$log_file" 2>/dev/null | head -n 1 || true)"
  reason="${reason_line#REVIEW_REQUIRED: }"
  query_line="$(grep '^QUERY:' "$log_file" 2>/dev/null | head -n 1 || true)"
  source_line="$(grep '^SOURCE:' "$log_file" 2>/dev/null | head -n 1 || true)"
  hint_line="$(grep '^SELECTION_HINT:' "$log_file" 2>/dev/null | head -n 1 || true)"
  selection_error="$(grep '^SELECTION_ERROR:' "$log_file" 2>/dev/null | head -n 1 || true)"

  cocoloop::print_kv "COMMAND" "install"
  cocoloop::print_kv "STATUS" "review-required"
  cocoloop::print_kv "INPUT_TYPE" "$input_type"
  cocoloop::print_kv "AGENT" "$agent_name"
  cocoloop::print_kv "FORCE" "$force"
  cocoloop::print_kv "REASON" "$reason"
  [[ -n "$query_line" ]] && cocoloop::print_kv "QUERY" "${query_line#QUERY: }"
  [[ -n "$source_line" ]] && cocoloop::print_kv "SOURCE" "${source_line#SOURCE: }"
  [[ -n "$selection_error" ]] && cocoloop::print_kv "SELECTION_ERROR" "${selection_error#SELECTION_ERROR: }"
  printf 'CANDIDATES:\n'
  while IFS= read -r candidate_line; do
    [[ -n "$candidate_line" ]] || continue
    candidate_line="${candidate_line#CANDIDATE: }"
    IFS=$'\t' read -r candidate_name candidate_meta candidate_path <<<"$candidate_line"
    if [[ "$reason" == "official-search-results" ]]; then
      printf '  - %s | id=%s | download=%s\n' "$candidate_name" "$candidate_meta" "${candidate_path:--}"
    elif [[ -n "${candidate_meta:-}" && -z "${candidate_path:-}" ]]; then
      printf '  - %s | path=%s\n' "$candidate_name" "$candidate_meta"
    elif [[ -n "${candidate_path:-}" ]]; then
      printf '  - %s | path=%s\n' "$candidate_name" "$candidate_path"
    else
      printf '  - %s\n' "$candidate_name"
    fi
  done < <(grep '^CANDIDATE:' "$log_file" 2>/dev/null || true)
  cocoloop::print_kv "NEXT_STEP" "agent-judgment-or-user-confirmation"
  [[ -n "$hint_line" ]] && cocoloop::print_kv "SELECTION_HINT" "${hint_line#SELECTION_HINT: }"
}

cocoloop::install::plan() {
  local source_arg="$1"
  local scope="$2"
  local force="$3"
  local selected_skills="${4:-}"
  local install_all="${5:-false}"
  local agent_name input_type target_path batch_reason failure_reason detail

  agent_name="$(cocoloop::platform::detect_agent)"
  input_type="$(cocoloop::install::infer_type "$source_arg")"

  batch_reason="$(cocoloop::install::batch_support_reason "$input_type" "$agent_name")"
  if [[ "$batch_reason" != "batch-supported" ]]; then
    detail=""
    if [[ "$batch_reason" == "missing-tools" ]]; then
      detail="$(cocoloop::install::missing_tools "$input_type" | paste -sd ',' - 2>/dev/null || true)"
    fi
    cocoloop::install::handoff "$source_arg" "$scope" "$force" "$input_type" "$agent_name" "$batch_reason" "$detail"
    return 0
  fi

  if cocoloop::install::run_batch "$source_arg" "$scope" "$force" "$input_type" "$selected_skills" "$install_all"; then
    return 0
  fi

  failure_reason="$(cocoloop::install::classify_batch_failure "$source_arg" "$input_type")"
  if [[ "$failure_reason" == "review-required" ]]; then
    cocoloop::install::print_review_from_log "$source_arg" "$scope" "$force" "$input_type" "$agent_name"
    return 0
  fi
  detail="$(cat "$(cocoloop::install::last_error_file)" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g' | sed 's/^ //; s/ $//' || true)"
  cocoloop::install::handoff "$source_arg" "$scope" "$force" "$input_type" "$agent_name" "$failure_reason" "$detail"
  return 0
}
