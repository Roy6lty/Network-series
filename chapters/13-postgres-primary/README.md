# Chapter 13: PostgreSQL Primary

![Chapter 13 routed PostgreSQL primary](diagram.svg)

## Key Concepts

### TCP is transport, not SQL

A TCP handshake proves that a client can reach a listening port. It does not
prove that PostgreSQL accepted credentials, selected the expected database, or
authorized a SQL statement.

```text
nc -vz 10.10.21.20 5432
    = TCP transport test

psql ... -c 'SELECT ...'
    = PostgreSQL protocol, authentication, and SQL test
```

### Routing, firewall, and PostgreSQL policy are separate

The application-to-database path crosses several boundaries:

```text
app route
    |
    v
lab-router FORWARD rule
    |
    v
PostgreSQL TCP listener
    |
    v
pg_hba.conf and password authentication
    |
    v
SQL authorization and execution
```

`iptables` on `lab-router` decides whether a forwarded packet may cross the
router. `pg_hba.conf` is evaluated by PostgreSQL after the connection reaches
the database server. Neither one installs a route.

### The primary is writable

`postgres-primary` is the writable database in `db_a`. Its Compose command
enables the settings needed by the later physical replication chapter:

```text
wal_level=replica
max_wal_senders=10
listen_addresses=*
```

The primary generates WAL when it changes data. A replica will consume that WAL
in a later chapter.

## Goal

Add `postgres-primary` to the routed database tier and validate the path from
both application networks at the TCP, PostgreSQL, and SQL layers.

By the end, you should be able to:

- identify the primary's address and return routes;
- explain why the application route uses `lab-router`;
- distinguish a TCP handshake from SQL authentication;
- explain the order of `FORWARD`, TCP listening, and `pg_hba.conf`;
- confirm that the primary is writable and ready for replication.

## From Chapter 12

Chapter 12 added public Nginx reverse proxies and Python app listeners. Those
HTTP paths remain in the cumulative stack, but the database path does not use
Nginx:

```text
app-a-test -> lab-router -> postgres-primary
app-b-test -> lab-router -> postgres-primary
```

The app routes to `db_a` through the router interface on its own subnet:

```text
app-a-test 10.10.11.10 -> 10.10.11.2
app-b-test 10.10.12.10 -> 10.10.12.2
```

The primary's return routes use its local router address, `10.10.21.2`, for
both application subnets.

## What This Stage Adds

The overlay adds one service and one named data volume:

```text
postgres-primary
    10.10.21.20 on db_a
    TCP 5432
    named volume: postgres_primary_data
```

Its lab entrypoint runs these routes before delegating to the official
PostgreSQL entrypoint:

```bash
ip route replace 10.10.11.0/24 via 10.10.21.2
ip route replace 10.10.12.0/24 via 10.10.21.2
ip route replace 10.10.22.0/24 via 10.10.21.2
```

On a fresh named volume, `init.sql` creates:

```text
replicator role with REPLICATION and LOGIN
users table
primary-seed row
```

The host-only lab credentials are `labadmin` / `postgres`. The replication
role uses `replicator` / `replica_password` for later chapters.

## Progress

- [ ] I can find `postgres-primary` at `10.10.21.20:5432`.
- [ ] I can identify the app forward route and primary return route.
- [ ] I can prove TCP reachability separately from SQL authentication.
- [ ] I can explain the roles of `iptables` and `pg_hba.conf`.
- [ ] I can prove the primary is writable and configured for future WAL sending.
- [ ] I can recover the primary after removing one return route.

## Tasks

### 1. Start the primary and wait for readiness

**Predict:** The cumulative stage should contain all Chapter 12 services plus
`postgres-primary`. The healthcheck should eventually report that PostgreSQL is
accepting connections.

**Run:**

```bash
bash scripts/compose-stage.sh 13 up -d --build --wait
bash scripts/compose-stage.sh 13 ps
bash scripts/compose-stage.sh 13 exec postgres-primary \
  pg_isready -U labadmin -d labdb
```

**Observe:** `postgres-primary` should be running, and `pg_isready` should
report that the server is accepting connections. On a new volume, the logs may
also show the normal PostgreSQL initialization and the mounted `init.sql`.

**Explain:** The healthcheck is a readiness check for PostgreSQL, not a proof
that an application can route to it. The client route, router firewall, and
database return path still need separate tests.

### 2. Inspect the database address and both route decisions

**Predict:** The primary should have an interface in `db_a` and explicit return
routes to both app networks. `app-a-test` should select the router on `app_a`,
while `lab-router` should select its directly connected `db_a` interface.

**Run:**

```bash
bash scripts/compose-stage.sh 13 exec postgres-primary ip addr
bash scripts/compose-stage.sh 13 exec postgres-primary ip route

bash scripts/compose-stage.sh 13 exec app-a-test \
  ip route get 10.10.21.20

bash scripts/compose-stage.sh 13 exec lab-router \
  ip route get 10.10.21.20
```

**Observe:** The important results should include:

```text
postgres-primary: 10.10.21.20/24
primary return:   10.10.11.0/24 via 10.10.21.2
                  10.10.12.0/24 via 10.10.21.2
app-a route:      10.10.21.20 via 10.10.11.2
router route:     10.10.21.20 dev <db_a-interface> src 10.10.21.2
```

The exact interface names and extra route fields can vary.

**Explain:** `app-a-test` cannot use `10.10.21.2` as its first next hop because
that address is not on `app_a`. It uses `10.10.11.2`, the router address on its
own subnet. The router then uses its directly connected `db_a` route. The
primary needs a return route because a TCP exchange travels in both directions.

### 3. Prove the TCP path from both app networks

**Predict:** Both app-to-primary TCP handshakes should succeed. The matching
TCP 5432 `FORWARD` counters on `lab-router` should increase.

**Run:** Capture the rules before and after the tests:

```bash
bash scripts/compose-stage.sh 13 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers

bash scripts/compose-stage.sh 13 exec app-a-test \
  nc -vz -w 3 10.10.21.20 5432

bash scripts/compose-stage.sh 13 exec app-b-test \
  nc -vz -w 3 10.10.21.20 5432

bash scripts/compose-stage.sh 13 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

**Observe:** `nc` should report that port 5432 is open from both app
containers. The counters for the app-to-`db_a` TCP 5432 rules should be higher
after the tests. The established return rule accounts for reply packets.

**Explain:** `nc -z` does not send a SQL query. It tests the route, the
router's `FORWARD` decision, the primary's TCP listener, and the return path.
It does not test `labadmin`, `labdb`, `pg_hba.conf` authentication, or SQL.

### 4. Test PostgreSQL authentication, SQL, and primary state

**Predict:** A TCP connection using the lab credentials should pass the host
rule in `pg_hba.conf`. The server should report `pg_is_in_recovery()` as `f`,
and an insert should succeed because this is the writable primary.

**Run:** The lab-tools image intentionally contains network tools, not `psql`.
Use the PostgreSQL client installed in `postgres-primary`; the `-h` option
makes this an explicit TCP and host-authentication test from that container.

```bash
bash scripts/compose-stage.sh 13 exec postgres-primary \
  env PGPASSWORD=postgres psql -h 10.10.21.20 -U labadmin -d labdb \
  -c 'SELECT current_user, current_database(), pg_is_in_recovery();'

bash scripts/compose-stage.sh 13 exec postgres-primary \
  psql -U labadmin -d labdb -c 'SELECT id, name FROM users ORDER BY id;'

bash scripts/compose-stage.sh 13 exec postgres-primary \
  psql -U labadmin -d labdb \
  -c "INSERT INTO users (name) VALUES ('chapter-13-check') RETURNING id, name;"

bash scripts/compose-stage.sh 13 exec postgres-primary \
  psql -U labadmin -d labdb -c 'SHOW wal_level; SHOW max_wal_senders;'

bash scripts/compose-stage.sh 13 exec postgres-primary \
  cat /etc/postgresql/pg_hba.conf
```

**Observe:** The TCP `psql` query should show user `labadmin`, database
`labdb`, and `f` for `pg_is_in_recovery()`. A fresh volume should contain the
`primary-seed` row; an existing named volume may also contain rows from earlier
runs. The insert should return a new row. `wal_level` should be `replica` and
`max_wal_senders` should be `10`.

**Explain:** The local `psql` command that reads `users` uses the container's
local PostgreSQL access path, while the `-h 10.10.21.20` command exercises a
TCP connection and the host rule. Neither command should be described as an
app-container route test; the `nc` commands performed that transport test.

The layer order is:

```text
route -> router FORWARD -> TCP 5432 -> pg_hba.conf -> password -> SQL
```

## Expected Observations

```text
app-a-test 10.10.11.10
        |
        | route via 10.10.11.2
        v
lab-router
        |
        | connected db_a route, FORWARD TCP/5432 allowed
        v
postgres-primary 10.10.21.20:5432
        |
        | return via 10.10.21.2
        v
app-a-test
```

The B-side request follows the same pattern through `10.10.12.2` and returns
through the primary's `10.10.21.2` interface.

An interpretation guide:

| Observation | First layer to investigate |
|---|---|
| No route from `ip route get` | Endpoint route or next hop |
| TCP timeout | Route, `FORWARD` drop, or missing return route |
| Connection refused | Host reached, but no listener accepted the port |
| PostgreSQL password error | TCP reached PostgreSQL; inspect credentials or `pg_hba.conf` |
| SQL permission error | PostgreSQL authentication passed; inspect database privileges |

## Checkpoint: Definition of Done

You are done when you can answer all of these:

1. Why does `app-a-test` use `10.10.11.2` as its next hop?
2. Why does the primary return through `10.10.21.2`?
3. What does a successful `nc` prove, and what does it not prove?
4. Where does the router's `FORWARD` rule run?
5. Where does `pg_hba.conf` run?
6. Why is `pg_is_in_recovery()` false on this service?
7. Why do the replication settings exist before a replica exists?

The progress checklist should be complete, both app TCP tests should succeed,
and the SQL write should succeed.

## Break It

Remove only the primary's return route to `app_a`.

**Predict:** The app-to-primary request may reach the primary, but the reply
will have no route back to `10.10.11.0/24`. The client-side TCP test should
hang until its three-second timeout even though the router's forward rule is
still present.

**Run:**

```bash
bash scripts/compose-stage.sh 13 exec postgres-primary \
  ip route delete 10.10.11.0/24 via 10.10.21.2

bash scripts/compose-stage.sh 13 exec postgres-primary ip route

bash scripts/compose-stage.sh 13 exec app-a-test \
  sh -c 'nc -vz -w 3 10.10.21.20 5432 || true'
```

**Observe:** The route to `10.10.11.0/24` should be absent. The client-side
`nc` command should time out or otherwise fail, while the router's permitted
TCP counter may still show that the forward packet arrived.

**Explain:** A route in the forward direction is not enough for a TCP
handshake. The primary's custom entrypoint installed the missing route during
container creation, so recreation is the intended recovery rather than a
manual host change.

**Recover:** Recreate only the primary. The named volume is not removed, so
database contents remain available:

```bash
bash scripts/compose-stage.sh 13 up -d --force-recreate postgres-primary
bash scripts/compose-stage.sh 13 exec postgres-primary \
  ip route get 10.10.11.10
bash scripts/compose-stage.sh 13 exec postgres-primary \
  pg_isready -U labadmin -d labdb
bash scripts/compose-stage.sh 13 exec app-a-test \
  nc -vz -w 3 10.10.21.20 5432
```

## Clean Up

Remove the containers and networks for this stage:

```bash
bash scripts/compose-stage.sh 13 down
```

Do not add `-v` unless you intentionally want to delete the named
`postgres_primary_data` volume and repeat first-time initialization.

## Conclusion: Next Chapter

The primary chapter connected routing, firewalling, TCP, PostgreSQL host
authentication, and SQL without treating them as one layer. The next chapter
uses this same primary to inspect its OS process tree and to contrast PostgreSQL
processes with shell job control.
