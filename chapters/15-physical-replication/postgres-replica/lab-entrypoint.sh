#!/bin/sh
set -eu

ip route replace 10.10.21.0/24 via 10.10.22.2
ip route replace 10.10.11.0/24 via 10.10.22.2
ip route replace 10.10.12.0/24 via 10.10.22.2

exec /usr/local/bin/docker-entrypoint.sh "$@"
