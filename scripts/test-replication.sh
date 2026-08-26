#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner=(bash "$root_dir/scripts/compose-stage.sh" 17)

printf 'Replication checkpoint\n'
"${runner[@]}" exec -T postgres-replica psql -U labadmin -d labdb -Atqc 'SELECT pg_is_in_recovery();'
"${runner[@]}" exec -T postgres-primary psql -U labadmin -d labdb -Atqc \
  "SELECT client_addr || ' ' || state FROM pg_stat_replication;"

"${runner[@]}" exec -T postgres-primary psql -U labadmin -d labdb -c \
  "INSERT INTO users (name) VALUES ('script-replication-test');"

for attempt in {1..20}; do
  if result="$("${runner[@]}" exec -T postgres-replica psql -U labadmin -d labdb -Atqc \
    "SELECT name FROM users WHERE name = 'script-replication-test';")" && [[ -n "$result" ]]; then
    printf 'Replica received: %s\n' "$result"
    printf 'Replication checks passed.\n'
    exit 0
  fi
  sleep 1
done

printf 'Replica did not receive the test row.\n' >&2
exit 1
