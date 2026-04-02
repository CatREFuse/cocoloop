#!/usr/bin/env bash

cocoloop::die() {
  local code="$1"
  local message="$2"
  printf 'ERROR [%s] %s\n' "$code" "$message" >&2
  exit 1
}

cocoloop::require_file() {
  local path="$1"
  [[ -f "$path" ]] || cocoloop::die "missing_file" "找不到文件: $path"
}

cocoloop::trim_line_endings() {
  printf '%s' "$1" | tr -d '\r'
}

cocoloop::normalize_name() {
  cocoloop::trim_line_endings "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

cocoloop::skill_name_from_root() {
  local skill_root="$1"
  local skill_md="${skill_root}/SKILL.md"
  local name=""

  if [[ -f "$skill_md" ]]; then
    name="$(sed -nE 's/^name:[[:space:]]*"?([^"]+)"?/\1/p' "$skill_md" | head -n 1)"
  fi
  if [[ -z "$name" ]]; then
    name="$(basename "$skill_root")"
  fi

  cocoloop::normalize_name "$(cocoloop::trim_line_endings "$name")"
}

cocoloop::skill_query_variants() {
  local target="$1"
  local normalized

  target="$(cocoloop::trim_line_endings "$target")"
  normalized="$(cocoloop::normalize_name "$target")"

  {
    printf '%s\n' "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')"
    printf '%s\n' "$normalized"
    if [[ -n "$normalized" && "$normalized" != *s ]]; then
      printf '%s\n' "${normalized}s"
    fi
  } | awk 'NF && !seen[$0]++'
}

cocoloop::payload_exact_skill_item() {
  local payload="$1"
  local target="$2"
  local candidate item

  cocoloop::has_jq || return 1

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    item="$(jq -c --arg q "$candidate" '
      .data.items
      | map(select(((.name // .original_name // "") | ascii_downcase) == $q))
      | .[0] // empty
    ' <<<"$payload" | head -n 1)"
    if [[ -n "$item" && "$item" != "null" ]]; then
      printf '%s\n' "$item"
      return 0
    fi
  done < <(cocoloop::skill_query_variants "$target")

  return 1
}

cocoloop::resolve_exact_skill_item() {
  local target="$1"
  local query payload item

  while IFS= read -r query; do
    [[ -n "$query" ]] || continue
    payload="$(cocoloop_api_search "$query")"
    item="$(cocoloop::payload_exact_skill_item "$payload" "$target" || true)"
    if [[ -n "$item" ]]; then
      printf '%s\n' "$item"
      return 0
    fi
  done < <(cocoloop::skill_query_variants "$target")

  return 1
}

cocoloop::ensure_dir() {
  mkdir -p "$1"
}

cocoloop::has_jq() {
  command -v jq >/dev/null 2>&1
}

cocoloop::json_get() {
  local filter="$1"
  local payload="${2:-}"

  [[ -n "$payload" ]] || return 1
  cocoloop::has_jq || return 1

  jq -r "$filter" 2>/dev/null <<<"$payload"
}

cocoloop::json_get_first_nonempty() {
  local payload="${1:-}"
  shift || true

  [[ -n "$payload" ]] || return 1
  cocoloop::has_jq || return 1

  local filter
  for filter in "$@"; do
    local value
    value="$(jq -r "$filter // empty" 2>/dev/null <<<"$payload")"
    if [[ -n "$value" && "$value" != "null" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

cocoloop::print_kv() {
  local key="$1"
  local value="${2:-}"
  printf '%s: %s\n' "$key" "$value"
}
