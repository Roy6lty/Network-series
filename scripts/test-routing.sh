#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner=(bash "$root_dir/scripts/compose-stage.sh" 17)

printf 'Routing checkpoint\n'
"${runner[@]}" exec -T app-a-test ip route
"${runner[@]}" exec -T app-a-test ip route get 10.10.21.20
"${runner[@]}" exec -T app-a-test nc -vz -w 3 10.10.21.20 5432
printf 'Routing checks passed.\n'
