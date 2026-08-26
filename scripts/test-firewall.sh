#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner=(bash "$root_dir/scripts/compose-stage.sh" 17)

printf 'Firewall checkpoint\n'
"${runner[@]}" exec -T public-a-test curl --fail --silent --show-error --connect-timeout 3 http://10.10.1.3
"${runner[@]}" exec -T app-a-test nc -vz -w 3 10.10.21.20 5432

if "${runner[@]}" exec -T public-a-test curl --silent --show-error --connect-timeout 2 http://10.10.12.10:8000; then
  printf 'Unexpected public-a to app-b access.\n' >&2
  exit 1
fi

"${runner[@]}" exec -T lab-router iptables -L FORWARD -n -v --line-numbers
printf 'Firewall checks passed.\n'
