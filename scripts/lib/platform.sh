#!/usr/bin/env bash

cocoloop::platform::detect_os() {
  case "$(uname -s)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
    *) printf 'unknown' ;;
  esac
}

cocoloop::platform::detect_agent() {
  if [[ -d .opencode/skills || -f opencode.json || -f opencode.jsonc ]]; then
    printf 'opencode'
    return 0
  fi
  if [[ -d .agents/skills || -f AGENTS.md || -f agents/openai.yaml ]]; then
    printf 'codex'
    return 0
  fi
  if [[ -d .claude/skills || -f CLAUDE.md || -f .claude/settings.json ]]; then
    printf 'claude-code'
    return 0
  fi
  if [[ -d skills || -f .openclaw/openclaw.json ]]; then
    printf 'openclaw'
    return 0
  fi
  if [[ -d .molili/workspaces/default/active_skills ]]; then
    printf 'molili'
    return 0
  fi
  if [[ -n "${OPENCODE_CONFIG_DIR:-}" || -n "${OPENCODE_CONFIG:-}" || -d "$HOME/.config/opencode/skills" ]]; then
    printf 'opencode'
    return 0
  fi
  if [[ -d "$HOME/.agents/skills" || -d "$HOME/.codex/skills" || -f "$HOME/.codex/config.toml" ]]; then
    printf 'codex'
    return 0
  fi
  if [[ -d "$HOME/.claude/skills" || -f "$HOME/.claude/settings.json" ]]; then
    printf 'claude-code'
    return 0
  fi
  if [[ -d "$HOME/.openclaw/skills" || -f "$HOME/.openclaw/openclaw.json" ]]; then
    printf 'openclaw'
    return 0
  fi
  if [[ -d "$HOME/.molili/workspaces/default/active_skills" || -d "$HOME/.molili/workspaces/default" ]]; then
    printf 'molili'
    return 0
  fi
  printf 'unknown'
}

cocoloop::platform::supports_batch_install() {
  local agent_name="$1"
  case "$agent_name" in
    codex|claude-code|openclaw|molili|opencode) return 0 ;;
    *) return 1 ;;
  esac
}

cocoloop::platform::project_dir() {
  local agent_name="$1"
  case "$agent_name" in
    opencode) printf '.opencode/skills' ;;
    codex) printf '.agents/skills' ;;
    claude-code) printf '.claude/skills' ;;
    openclaw)
      if [[ -d .agents/skills ]]; then
        printf '.agents/skills'
      else
        printf 'skills'
      fi
      ;;
    molili) cocoloop::platform::user_dir "$agent_name" ;;
    *) cocoloop::die "unknown_agent" "未知 Agent 平台: $agent_name" ;;
  esac
}

cocoloop::platform::user_dir() {
  local agent_name="$1"
  case "$agent_name" in
    opencode) printf '%s/.config/opencode/skills' "$HOME" ;;
    codex) printf '%s/.agents/skills' "$HOME" ;;
    claude-code) printf '%s/.claude/skills' "$HOME" ;;
    openclaw)
      if [[ -d "$HOME/.openclaw/skills" || ! -d "$HOME/.agents/skills" ]]; then
        printf '%s/.openclaw/skills' "$HOME"
      else
        printf '%s/.agents/skills' "$HOME"
      fi
      ;;
    molili) printf '%s/.molili/workspaces/default/active_skills' "$HOME" ;;
    *) cocoloop::die "unknown_agent" "未知 Agent 平台: $agent_name" ;;
  esac
}

cocoloop::platform::resolve_target_root() {
  local scope="$1"
  local agent_name="$2"

  case "$scope" in
    auto|project)
      cocoloop::platform::project_dir "$agent_name"
      ;;
    user)
      cocoloop::platform::user_dir "$agent_name"
      ;;
    *)
      cocoloop::die "invalid_scope" "不支持的 scope: $scope。仅支持 auto、project、user。"
      ;;
  esac
}

cocoloop::platform::describe_paths() {
  local agent_name="$1"
  local os_platform="$2"
  cocoloop::print_kv "AGENT" "$agent_name"
  cocoloop::print_kv "OS" "$os_platform"
  cocoloop::print_kv "PROJECT_ROOT" "$(cocoloop::platform::project_dir "$agent_name")"
  cocoloop::print_kv "USER_ROOT" "$(cocoloop::platform::user_dir "$agent_name")"
}

cocoloop::platform::known_search_roots() {
  local agent_name root

  for agent_name in opencode codex claude-code openclaw molili; do
    root="$(cocoloop::platform::project_dir "$agent_name" 2>/dev/null || true)"
    if [[ -n "$root" && -d "$root" ]]; then
      printf '%s\tproject\t%s\n' "$agent_name" "$root"
    fi

    root="$(cocoloop::platform::user_dir "$agent_name" 2>/dev/null || true)"
    if [[ -n "$root" && -d "$root" ]]; then
      printf '%s\tuser\t%s\n' "$agent_name" "$root"
    fi
  done | awk -F '\t' '!seen[$1 FS $3]++'
}

cocoloop::platform::skill_matches_query() {
  local skill_name="$1"
  local query="$2"
  local variant skill_compact variant_compact

  skill_name="$(cocoloop::normalize_name "$skill_name")"
  skill_compact="$(printf '%s' "$skill_name" | tr -d '-')"

  while IFS= read -r variant; do
    [[ -n "$variant" ]] || continue
    variant="$(cocoloop::normalize_name "$variant")"
    variant_compact="$(printf '%s' "$variant" | tr -d '-')"
    if [[ "$skill_name" == "$variant" || "$skill_name" == *"$variant"* || "$skill_compact" == *"$variant_compact"* ]]; then
      return 0
    fi
  done < <(cocoloop::skill_query_variants "$query")

  return 1
}

cocoloop::platform::search_local_skills() {
  local query="$1"
  local agent_name scope root skill_root skill_name resolved_path

  while IFS=$'\t' read -r agent_name scope root; do
    [[ -n "$root" && -d "$root" ]] || continue
    while IFS= read -r skill_root; do
      [[ -n "$skill_root" && -f "$skill_root/SKILL.md" ]] || continue
      skill_name="$(cocoloop::skill_name_from_root "$skill_root")"
      cocoloop::platform::skill_matches_query "$skill_name" "$query" || continue
      resolved_path="$(cd "$skill_root" 2>/dev/null && pwd -P)"
      printf '%s\t%s\t%s\t%s\n' \
        "$skill_name" \
        "$agent_name" \
        "$scope" \
        "${resolved_path:-$skill_root}"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  done < <(cocoloop::platform::known_search_roots) | awk -F '\t' '!seen[$0]++'
}
