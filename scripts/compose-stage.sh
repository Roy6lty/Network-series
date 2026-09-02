#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  printf 'Usage: %s CHAPTER DOCKER_COMPOSE_COMMAND [ARGS...]\n' "$0" >&2
  exit 2
fi

stage="$1"
shift

if [[ "$stage" != "05b" ]] && { [[ ! "$stage" =~ ^[0-9]{2}$ ]] || ((10#$stage < 1 || 10#$stage > 17)); }; then
  printf 'Chapter must be a two-digit number from 01 through 17, or 05b.\n' >&2
  exit 2
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_files=()

if [[ "$stage" == "05b" ]]; then
  compose_file="$root_dir/chapters/05b-muliti-router/compose.yaml"
  if [[ ! -f "$compose_file" ]]; then
    printf 'Chapter 05b Compose file was not found at chapters/05b-muliti-router/compose.yaml.\n' >&2
    exit 1
  fi
  compose_files+=(-f "${compose_file#"$root_dir/"}")
else
  while IFS= read -r compose_file; do
    chapter_dir="${compose_file%/*}"
    chapter_name="${chapter_dir##*/}"
    chapter_number="${chapter_name%%-*}"

    if [[ ! "$chapter_number" =~ ^[0-9]{2}$ ]]; then
      continue
    fi

    if ((10#$chapter_number <= 10#$stage)); then
      compose_files+=(-f "${compose_file#"$root_dir/"}")
    fi
  done < <(LC_ALL=C printf '%s\n' "$root_dir"/chapters/*/compose.yaml | LC_ALL=C sort)
fi

exec docker compose \
  --project-directory "$root_dir" \
  "${compose_files[@]}" \
  "$@"
