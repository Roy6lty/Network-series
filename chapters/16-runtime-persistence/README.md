# Chapter 16: Runtime Configuration Persistence

![Chapter 16 persistent entrypoint flow](diagram.svg)

## Concepts

- **Runtime state** such as an `ip route` entry belongs to a container's
  network namespace. Recreating the container removes that state.
- A Docker **named volume** persists PostgreSQL cluster files independently of
  the container. This lets the replica keep its physical cluster across a
  restart or recreation.
- **Idempotent setup** can run repeatedly and converge on the same desired
  state. The entrypoint uses `ip route replace` rather than a fragile
  `ip route add`.
- **`PG_VERSION`** is the bootstrap sentinel in this lab. A non-empty sentinel
  means the replica volume already contains a cluster, so another
  `pg_basebackup` must not run.
- **`exec`** replaces the wrapper with the official PostgreSQL entrypoint so
  the real server receives signals and its exit status becomes the container
  exit status.

## Goal

Move the manual route and replica bootstrap from chapter 15 into an entrypoint,
then prove that container recreation reapplies routes without copying the
database again.

## Progression From Chapter 15

Chapter 15 created the standby by hand:

```text
enter replica -> clear directory -> pg_basebackup -> write .pgpass
             -> start postgres manually
```

That flow proves the replication concepts, but it is not a repeatable service
startup procedure. Chapter 16 makes the container perform the same work:

```text
container starts
        |
        +-- replace routes
        +-- if postgres and PG_VERSION is absent:
        |      wait for primary -> pg_basebackup -> write .pgpass
        +-- exec official PostgreSQL entrypoint
```

The named `postgres_replica_data` volume introduced with the chapter 15
service is now useful: the cluster survives container recreation while the
entrypoint reapplies ephemeral network state.

## What This Stage Adds

The chapter 16 Compose overlay changes the replica image and command. It sets:

```text
LAB_REPLICA_BOOTSTRAP=true
PRIMARY_HOST=10.10.21.20
REPLICA_PASSWORD=replica_password
```

The replica command is PostgreSQL with the lab HBA file:

```text
postgres -c hba_file=/etc/postgresql/replica-pg_hba.conf
```

The entrypoint in
`chapters/16-runtime-persistence/postgres-replica/lab-entrypoint.sh` then:

1. installs the three replica routes with `ip route replace`;
2. checks that the requested command is `postgres`;
3. checks `LAB_REPLICA_BOOTSTRAP` and that `PG_VERSION` is absent or empty;
4. waits for the primary and runs `pg_basebackup -R` once;
5. writes `/var/lib/postgresql/.pgpass` with mode `600`; and
6. runs `exec /usr/local/bin/docker-entrypoint.sh "$@"`.

## Progress Checklist

- [ ] Start chapter 16 with `--wait` and observe the health checks.
- [ ] Verify the replica routes and recovery state.
- [ ] Verify WAL streaming and a replicated insert.
- [ ] Recreate only `postgres-replica` and confirm its data remains.
- [ ] Confirm routes are reapplied and no second base backup is needed.
- [ ] Complete the route deletion break exercise and recover by recreation.

## Tasks

### 1. Start the Automated Replica

**Predict:** On an empty volume, what should happen before PostgreSQL becomes
healthy? On a populated volume, should `pg_basebackup` run again?

**Run:** From the repository root:

```bash
bash scripts/compose-stage.sh 16 up -d --build --wait
bash scripts/compose-stage.sh 16 ps
```

Inspect the resolved cumulative configuration if you want to see the overlay:

```bash
bash scripts/compose-stage.sh 16 config
```

**Observe:** `postgres-primary` becomes healthy first. The replica then waits
for the primary, bootstraps if its volume is empty, starts PostgreSQL, and
becomes healthy. `ps` shows the normal `postgres` command rather than
`sleep infinity` for the replica.

**Explain:** `depends_on` controls the initial Compose ordering, while the
entrypoint's `until pg_isready ...` loop protects the base backup from a
primary that is still starting. The health check is evidence that the final
server is accepting connections.

### 2. Inspect Routes and Recovery State

**Predict:** Which next hop should the replica use for the primary at
`10.10.21.20`? Will the replica report recovery mode?

**Run:**

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-replica ip route

bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  ip route get 10.10.21.20

bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  psql -U labadmin -d labdb -c 'SELECT pg_is_in_recovery();'

bash scripts/compose-stage.sh 16 exec -T postgres-primary \
  psql -U labadmin -d labdb -c \
  'SELECT client_addr, state FROM pg_stat_replication;'
```

**Observe:** The route lookup selects `10.10.22.2` as the next hop. The
replica returns `t`, and the primary reports `10.10.22.20` with state
`streaming`.

**Explain:** The route is runtime kernel state, so the entrypoint reapplies it
on every container start. The data files and `standby.signal` are on the named
volume, so the replica can start in recovery without a new base backup.

### 3. Prove WAL Replay

**Predict:** If the primary gets a new row, should the application write to
the replica or should WAL replay make the row visible there?

**Run:** Use the primary for the write and poll the replica briefly:

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-primary \
  psql -U labadmin -d labdb -c \
  "INSERT INTO users (name) VALUES ('runtime-persistence-test');"

sleep 2

bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  psql -U labadmin -d labdb -c \
  "SELECT name FROM users WHERE name = 'runtime-persistence-test';"
```

**Observe:** The row appears on the replica. A short delay is normal because
the primary commits first and the standby replays WAL asynchronously.

**Explain:** The entrypoint did not copy an SQL export. It preserved the
physical cluster and kept the `primary_conninfo` and `standby.signal` created
by `pg_basebackup -R`.

### 4. Inspect the Persistence Boundary

**Predict:** Which of these should survive recreation: a route in the network
namespace, or `PG_VERSION` in the named volume?

**Run:** Record both kinds of state:

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-replica sh -c \
  'set -e; cat /var/lib/postgresql/data/PG_VERSION; test -f /var/lib/postgresql/data/standby.signal; printf "standby.signal exists\n"; ip route get 10.10.21.20'
```

Recreate only the replica. Do not remove volumes:

```bash
bash scripts/compose-stage.sh 16 up -d --force-recreate --wait postgres-replica
```

Inspect the same state again:

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-replica sh -c \
  'set -e; cat /var/lib/postgresql/data/PG_VERSION; test -f /var/lib/postgresql/data/standby.signal; printf "standby.signal exists\n"; ip route get 10.10.21.20'

bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  psql -U labadmin -d labdb -c 'SELECT pg_is_in_recovery();'
```

**Observe:** `PG_VERSION` and `standby.signal` remain, and the route again uses
`10.10.22.2`. The replica starts in recovery without a manual base backup.

**Explain:** Recreation creates a new network namespace, so the old route is
gone. The named volume is mounted into the new container, so the physical
cluster remains. The entrypoint's route setup and `PG_VERSION` guard handle
the two kinds of state separately.

### 5. Demonstrate Idempotent Route Setup

**Predict:** What should happen if the same `ip route replace` command runs
again? Should it create duplicate equivalent routes?

**Run:** Repeat one of the exact entrypoint route commands:

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  ip route replace 10.10.21.0/24 via 10.10.22.2

bash scripts/compose-stage.sh 16 exec -T postgres-replica ip route
```

**Observe:** The route remains present once with the same next hop. The
container continues serving PostgreSQL.

**Explain:** `replace` converges on the desired route whether it was missing or
already present. This is why it is safe in an entrypoint that runs every time
the container starts. It does not make the route persistent by itself; the
entrypoint re-executes the command after recreation.

### 6. Observe the `exec` Boundary

**Predict:** After startup, should PostgreSQL be hidden behind a long-running
shell, or should the real server be the container's main process?

**Run:** Inspect the process tree:

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-replica ps -ef
```

**Observe:** The final PostgreSQL server is present as the main service
process, rather than a manually started child under `sleep infinity`.

**Explain:** The wrapper performs setup and then uses `exec`. Signal delivery,
shutdown, and the process exit status therefore follow the official
PostgreSQL entrypoint and server.

## Expected Observations

On a clean volume, the first startup looks conceptually like this:

```text
empty postgres_replica_data
        |
        v
route replace -> wait for primary -> pg_basebackup -R
        |
        v
PG_VERSION + standby.signal + .pgpass
        |
        v
official PostgreSQL entrypoint -> postgres in recovery
```

On recreation, it looks like this:

```text
existing postgres_replica_data
        |
        v
route replace -> PG_VERSION exists -> skip pg_basebackup
        |
        v
exec postgres -> resume WAL streaming
```

The database files persist. The route does not persist, but is restored before
the server starts.

## Checkpoint: Definition of Done

- [ ] `bash scripts/compose-stage.sh 16 up -d --build --wait` completes.
- [ ] The replica reports `pg_is_in_recovery() = t`.
- [ ] The primary reports the replica as `streaming`.
- [ ] A primary insert appears on the replica.
- [ ] The replica route to `10.10.21.20` uses `10.10.22.2`.
- [ ] Recreating only `postgres-replica` preserves `PG_VERSION` and recovery
      state.
- [ ] You can distinguish a persistent volume from ephemeral namespace state.

## Break It: Delete One Runtime Route

This is one controlled failure. It changes only a route in the live replica
namespace. It does not delete data and it does not edit a Compose file.

**Predict:** If the replica loses its route to `db_a`, will its local
PostgreSQL process immediately stop existing? Will a new WAL connection be able
to reach the primary?

**Run:** Delete only the route used to reach the primary:

```bash
bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  ip route delete 10.10.21.0/24 via 10.10.22.2

bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  ip route get 10.10.21.20
```

**Observe:** The route lookup falls back to another route, fails, or no longer
selects `10.10.22.2`. A local `psql` query may still work because the server
process and its local socket are separate from the missing network route.

**Explain:** A healthy process does not prove that its network dependency is
healthy. The existing replication TCP session may remain briefly, but the
replica cannot reliably reconnect to the primary without the route.

**Recover:** Recreate only the replica. The named volume is preserved and the
entrypoint reapplies the route:

```bash
bash scripts/compose-stage.sh 16 up -d --force-recreate --wait postgres-replica

bash scripts/compose-stage.sh 16 exec -T postgres-replica \
  ip route get 10.10.21.20

bash scripts/compose-stage.sh 16 exec -T postgres-primary \
  psql -U labadmin -d labdb -c \
  'SELECT client_addr, state FROM pg_stat_replication;'
```

The route should again use `10.10.22.2`, and the primary should return
`streaming` after the replica reconnects.

## Clean Up

Remove the chapter containers and networks while preserving both database
volumes:

```bash
bash scripts/compose-stage.sh 16 down
```

Do not use `down -v` as routine cleanup. It erases the evidence for the
volume-persistence lesson. A full reset is intentionally reserved for when the
replica or primary must be bootstrapped from empty data directories.

## Conclusion and Next Chapter

Chapter 16 turned manual work into repeatable startup behavior. Routes are
reapplied, the named volume preserves the physical cluster, the `PG_VERSION`
guard prevents an unsafe second base backup, and `exec` leaves PostgreSQL with
the correct process boundary.

Chapter 17 is the capstone. It runs the repository's routing, firewall, NAT,
and replication checks together, then uses one controlled route failure to
practice finding the first broken layer and recovering it.
