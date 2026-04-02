#!/usr/bin/env bash

# Fallback discovery helpers.

cocoloop_fallback_github_search_url() {
  local query="${1:-}"
  local encoded
  encoded="$(cocoloop_api_urlencode "${query} SKILL.md")"
  printf 'https://github.com/search?q=%s&type=repositories\n' "$encoded"
}

cocoloop_fallback_skills_sh_url() {
  local query="${1:-}"
  local encoded
  encoded="$(cocoloop_api_urlencode "$query")"
  printf 'https://skills.sh/search?q=%s\n' "$encoded"
}

cocoloop_fallback_clawhub_url() {
  local query="${1:-}"
  local encoded
  encoded="$(cocoloop_api_urlencode "$query")"
  printf 'https://clawhub.ai/search?q=%s\n' "$encoded"
}

cocoloop_fallback_candidates_json() {
  local query="${1:-}"
  printf '{\n'
  printf '  "query": "%s",\n' "$query"
  printf '  "sources": [\n'
  printf '    {"source":"clawhub","url":"%s"},\n' "$(cocoloop_fallback_clawhub_url "$query")"
  printf '    {"source":"skills.sh","url":"%s"},\n' "$(cocoloop_fallback_skills_sh_url "$query")"
  printf '    {"source":"github","url":"%s"}\n' "$(cocoloop_fallback_github_search_url "$query")"
  printf '  ]\n'
  printf '}\n'
}

cocoloop_fallback_find() {
  local query="${1:-}"
  cocoloop_fallback_candidates_json "$query"
}

cocoloop_fallback_build_candidate_payload() {
  local name="${1:-}"
  local brief="${2:-}"
  local source_url="${3:-}"
  printf '{"original_name":"%s","brief":"%s","download_url":"%s"}\n' "$name" "$brief" "$source_url"
}
