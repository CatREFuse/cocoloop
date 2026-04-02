#!/usr/bin/env bash

cocoloop::uninstall::candidate_paths() {
  local skill_name="$1"
  local normalized
  normalized="$(cocoloop::normalize_name "$skill_name")"
  printf '.opencode/skills/%s\n' "$normalized"
  printf '%s/.config/opencode/skills/%s\n' "$HOME" "$normalized"
  printf '.agents/skills/%s\n' "$normalized"
  printf '%s/.agents/skills/%s\n' "$HOME" "$normalized"
  printf '%s/.codex/skills/%s\n' "$HOME" "$normalized"
  printf '.claude/skills/%s\n' "$normalized"
  printf '%s/.claude/skills/%s\n' "$HOME" "$normalized"
  printf 'skills/%s\n' "$normalized"
  printf '%s/.openclaw/skills/%s\n' "$HOME" "$normalized"
  printf '%s/.molili/workspaces/default/active_skills/%s\n' "$HOME" "$normalized"
}

cocoloop::uninstall::filtered_paths() {
  local skill_name="$1"
  local scope="$2"

  case "$scope" in
    all)
      cocoloop::uninstall::candidate_paths "$skill_name"
      ;;
    project)
      cocoloop::uninstall::candidate_paths "$skill_name" | grep -E '^\.(opencode|agents|claude)/skills/|^skills/'
      ;;
    user)
      cocoloop::uninstall::candidate_paths "$skill_name" | grep -E "^${HOME//\//\\/}/"
      ;;
    *)
      cocoloop::die "invalid_scope" "uninstall 仅支持 --scope all|project|user。"
      ;;
  esac
}

cocoloop::uninstall::plan() {
  local skill_name="$1"
  local scope="$2"
  local removed=0
  local store_removed="no"
  local path
  local normalized store_path

  normalized="$(cocoloop::normalize_name "$skill_name")"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -d "$path" || -L "$path" ]]; then
      rm -rf "$path"
      removed=$((removed + 1))
      printf 'REMOVED: %s\n' "$path"
    fi
  done < <(cocoloop::uninstall::filtered_paths "$skill_name" "$scope")

  store_path="$(cocoloop_skills_store_dir)/$normalized"
  if [[ -d "$store_path" || -L "$store_path" ]]; then
    rm -rf "$store_path"
    store_removed="yes"
    printf 'REMOVED_STORE: %s\n' "$store_path"
  fi

  if [[ "$removed" -gt 0 || "$store_removed" == "yes" ]]; then
    cocoloop_session_remove_install "$normalized"
  fi

  cocoloop::print_kv "COMMAND" "uninstall"
  cocoloop::print_kv "SKILL" "$skill_name"
  cocoloop::print_kv "SCOPE" "$scope"
  cocoloop::print_kv "REMOVED_COUNT" "$removed"
  cocoloop::print_kv "STORE_REMOVED" "$store_removed"

  if [[ "$removed" -eq 0 && "$store_removed" != "yes" ]]; then
    printf 'CANDIDATE_PATHS:\n'
    cocoloop::uninstall::filtered_paths "$skill_name" "$scope" | sed 's/^/  - /'
  else
    cocoloop::print_kv "STATUS" "removed"
  fi
}
