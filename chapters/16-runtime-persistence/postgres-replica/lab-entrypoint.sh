#!/bin/sh
set -eu

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
export PGDATA

ip route replace 10.10.21.0/24 via 10.10.22.2
ip route replace 10.10.11.0/24 via 10.10.22.2
ip route replace 10.10.12.0/24 via 10.10.22.2

if [ "${1:-}" = "postgres" ] \
  && [ "${LAB_REPLICA_BOOTSTRAP:-false}" = "true" ] \
  && [ ! -s "$PGDATA/PG_VERSION" ]; then
  : "${PRIMARY_HOST:?PRIMARY_HOST is required}"
  : "${REPLICA_PASSWORD:?REPLICA_PASSWORD is required}"

  install -d -o postgres -g postgres -m 700 "$PGDATA"

  until pg_isready -h "$PRIMARY_HOST" -p 5432 -U replicator -d replication; do
    sleep 2
  done

  PGPASSWORD="$REPLICA_PASSWORD" gosu postgres pg_basebackup \
    -h "$PRIMARY_HOST" \
    -U replicator \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -P \
    -R

  printf '*:*:*:replicator:%s\n' "$REPLICA_PASSWORD" > /var/lib/postgresql/.pgpass
  chown postgres:postgres /var/lib/postgresql/.pgpass
  chmod 600 /var/lib/postgresql/.pgpass
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
