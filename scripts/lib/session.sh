#!/usr/bin/env bash

# Session helpers for Cocoloop CLI.

cocoloop_state_root() {
  printf '%s\n' "${COCOLOOP_HOME:-$HOME/.cocoloop}"
}

cocoloop_cache_dir() {
  printf '%s/cache\n' "$(cocoloop_state_root)"
}

cocoloop_logs_dir() {
  printf '%s/logs\n' "$(cocoloop_state_root)"
}

cocoloop_data_dir() {
  printf '%s/state\n' "$(cocoloop_state_root)"
}

cocoloop_skills_store_dir() {
  printf '%s/skills\n' "$(cocoloop_state_root)"
}

cocoloop_installs_file() {
  printf '%s/installs.tsv\n' "$(cocoloop_data_dir)"
}

cocoloop_likes_file() {
  printf '%s/likes.txt\n' "$(cocoloop_data_dir)"
}

cocoloop_session_init_dirs() {
  mkdir -p "$(cocoloop_cache_dir)" "$(cocoloop_logs_dir)" "$(cocoloop_data_dir)" "$(cocoloop_skills_store_dir)"
}

cocoloop_session_record_install() {
  local skill_name="$1"
  local target_path="$2"
  local source="$3"
  local source_type="$4"
  local version="$5"
  local scope="$6"
  local installs_file

  cocoloop_session_init_dirs
  installs_file="$(cocoloop_installs_file)"
  [[ -f "$installs_file" ]] || : >"$installs_file"

  skill_name="$(cocoloop::normalize_name "$skill_name")"
  target_path="$(cocoloop::trim_line_endings "$target_path")"
  source="$(cocoloop::trim_line_endings "$source")"
  source_type="$(cocoloop::trim_line_endings "$source_type")"
  version="$(cocoloop::trim_line_endings "$version")"
  scope="$(cocoloop::trim_line_endings "$scope")"

  awk -F '\t' -v skill="$skill_name" '$1 != skill' "$installs_file" >"${installs_file}.tmp" || true
  mv "${installs_file}.tmp" "$installs_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$skill_name" \
    "$target_path" \
    "$source" \
    "$source_type" \
    "$version" \
    "$scope" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$installs_file"
}

cocoloop_session_find_install() {
  local skill_name="$1"
  local installs_file
  installs_file="$(cocoloop_installs_file)"
  [[ -f "$installs_file" ]] || return 1
  awk -F '\t' -v skill="$skill_name" '{
    normalized=$1
    gsub(/\r/, "", normalized)
    if (normalized == skill) {
      print
      exit
    }
  }' "$installs_file"
}

cocoloop_session_remove_install() {
  local skill_name="$1"
  local installs_file
  installs_file="$(cocoloop_installs_file)"
  [[ -f "$installs_file" ]] || return 0
  awk -F '\t' -v skill="$skill_name" '{
    normalized=$1
    gsub(/\r/, "", normalized)
    if (normalized != skill) {
      print
    }
  }' "$installs_file" >"${installs_file}.tmp" || true
  mv "${installs_file}.tmp" "$installs_file"
}

cocoloop_session_add_like() {
  local skill_name="$1"
  local likes_file
  cocoloop_session_init_dirs
  likes_file="$(cocoloop_likes_file)"
  [[ -f "$likes_file" ]] || : >"$likes_file"
  grep -Fxq "$skill_name" "$likes_file" 2>/dev/null || printf '%s\n' "$skill_name" >>"$likes_file"
}

cocoloop_session_list_likes() {
  local likes_file
  likes_file="$(cocoloop_likes_file)"
  [[ -f "$likes_file" ]] || return 0
  cat "$likes_file"
}
