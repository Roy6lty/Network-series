#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner=(bash "$root_dir/scripts/compose-stage.sh" 17)

printf 'NAT checkpoint\n'
"${runner[@]}" exec -T app-a-test curl --fail --silent --show-error --connect-timeout 3 http://10.10.30.10:8080
"${runner[@]}" exec -T nat-gateway ip route
"${runner[@]}" exec -T nat-gateway iptables -t nat -L POSTROUTING -n -v
printf 'NAT checks passed.\n'
