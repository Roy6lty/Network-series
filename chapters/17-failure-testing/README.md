# Chapter 17: Failure Testing and Cloud Mapping

![Chapter 17 final architecture and failure boundaries](diagram.svg)

## Concepts

- A **failure experiment** changes one dependency at a time, records the
  symptom, identifies the first broken layer, and restores the dependency.
- The diagnostic order is:

```text
route -> neighbor -> packet capture -> firewall -> TCP listener
       -> application protocol -> authentication
```

- A successful check at one layer does not prove that later layers work. A
  route can be correct while a firewall drops the packet; a TCP connection can
  work while PostgreSQL rejects authentication.
- The cloud comparison is a design analogy. Docker does not provide a managed
  VPC, managed NAT gateway, load balancer, or database failover service merely
  because this lab contains similar components.

## Goal

Validate the complete cumulative architecture with the repository's actual
check scripts, collect observable pass/fail evidence at each layer, and use
one controlled route failure to practice diagnosis and recovery.

## Progression From Chapter 16

Chapter 16 made the database standby repeatable. The final stack now contains
all earlier lessons:

```text
process -> interface -> route -> next hop -> forwarding -> firewall
        -> NAT -> DNS/proxy -> PostgreSQL -> physical replication
```

Chapter 17 adds no new network device. It is the verification and failure
analysis stage for the architecture built in chapters 01 through 16.

## What This Stage Adds

The chapter Compose file intentionally contains no service changes:

```yaml
services: {}
```

The cumulative runner still loads every numbered Compose file through chapter
17. The repository root scripts provide the capstone checks:

```text
scripts/test-routing.sh
scripts/test-firewall.sh
scripts/test-nat.sh
scripts/test-replication.sh
```

Together they check:

```text
static routes and TCP database reachability
stateful FORWARD rules and public reverse-proxy access
private egress through MASQUERADE
physical standby recovery, streaming, and WAL replay
```

## Progress Checklist

- [ ] Start the final cumulative stack and confirm all services are up.
- [ ] Run the routing checkpoint and capture its successful route and TCP
      evidence.
- [ ] Run the firewall checkpoint and observe both allowed and denied paths.
- [ ] Run the NAT checkpoint and observe the egress route and MASQUERADE rule.
- [ ] Run the replication checkpoint and observe the row on the standby.
- [ ] Complete the controlled route failure and verify the expected failure.
- [ ] Recreate the affected endpoint and rerun all four checks.
- [ ] Explain the failure matrix and the bounded cloud mapping.

## Tasks

### 1. Start and Baseline the Final Stack

**Predict:** Since chapter 17 adds no service, should the final stack have the
same major components as chapter 16? Which service should be healthy before the
replica bootstraps?

**Run:**

```bash
bash scripts/compose-stage.sh 17 up -d --build --wait
bash scripts/compose-stage.sh 17 ps
```

**Observe:** The cumulative stack includes the six diagnostic endpoints,
`lab-router`, `nat-gateway`, `nat-public-test`, `nginx-a`, `nginx-b`,
`postgres-primary`, and `postgres-replica`. The primary becomes healthy before
the persistent replica completes its startup.

**Explain:** `scripts/compose-stage.sh` layers the Compose files in chapter
order. Chapter 17 is a capstone because the behavior under test was introduced
earlier rather than hidden in a new final Compose file.

### 2. Run the Routing Checkpoint

**Predict:** From `app-a-test`, which next hop should reach
`postgres-primary` at `10.10.21.20`? Should the TCP connection to port `5432`
complete?

**Run:**

```bash
bash scripts/test-routing.sh
```

For direct evidence, also inspect the route decision and listener:

```bash
bash scripts/compose-stage.sh 17 exec -T app-a-test \
  ip route get 10.10.21.20

bash scripts/compose-stage.sh 17 exec -T postgres-primary ss -lnt
```

**Observe:** The route lookup uses:

```text
10.10.21.20 via 10.10.11.2 dev eth0 src 10.10.11.10
```

The `nc` command in the script succeeds and the script ends with:

```text
Routing checks passed.
```

The primary listener includes TCP port `5432`.

**Explain:** The endpoint route selects the router's local `app_a` address.
The router has a connected `db_a` route and its firewall allows app-to-db TCP
`5432`. The primary entrypoint supplies the return route through
`10.10.21.2`.

### 3. Run the Firewall Checkpoint

**Predict:** Which path should be allowed: `public-a-test` to `nginx-a` on
port 80, or `public-a-test` directly to `app-b-test` on port 8000? What should
the default `FORWARD` policy be?

**Run:**

```bash
bash scripts/test-firewall.sh
```

Inspect the rule counters after the script:

```bash
bash scripts/compose-stage.sh 17 exec -T lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

**Observe:** The public request to `10.10.1.3` succeeds. The app-to-primary
TCP check succeeds. The script intentionally tries public-a to app-b and
expects that request to fail; the script still ends with:

```text
Firewall checks passed.
```

The router's `FORWARD` policy is `DROP`, with explicit allow rules and an
`ESTABLISHED,RELATED` rule.

**Explain:** `FORWARD` controls packets crossing router interfaces. It is not
the same as a container's local `INPUT` chain or PostgreSQL's `pg_hba.conf`.
The Nginx request has two TCP sessions: public client to Nginx, then Nginx to
the app. The allow rule applies to the second, forwarded session.

### 4. Run the NAT Checkpoint

**Predict:** What should be the default next hop from `app-a-test` for the
private egress test? Which source address should `nat-public-test` observe?

**Run:**

```bash
bash scripts/test-nat.sh
```

Inspect the NAT gateway directly:

```bash
bash scripts/compose-stage.sh 17 exec -T nat-gateway ip route

bash scripts/compose-stage.sh 17 exec -T nat-gateway \
  iptables -t nat -L POSTROUTING -n -v
```

**Observe:** The request from `app-a-test` reaches `10.10.30.10:8080`, and the
script ends with:

```text
NAT checks passed.
```

The NAT gateway has a public-side route through `10.10.30.1` and
`POSTROUTING` contains `MASQUERADE` rules for `10.10.11.0/24` and
`10.10.12.0/24`.

**Explain:** Routing chooses `10.10.11.3` as the app's default next hop. The
NAT gateway chooses its `nat_public` interface, then MASQUERADE rewrites the
private source to the gateway's public-side address. Conntrack allows the
reply to be translated back.

### 5. Run the Replication Checkpoint

**Predict:** What should the standby recovery query return? Where should the
test row be written, and how will it reach the replica?

**Run:**

```bash
bash scripts/test-replication.sh
```

For the two state queries used by the script, run:

```bash
bash scripts/compose-stage.sh 17 exec -T postgres-replica \
  psql -U labadmin -d labdb -Atqc 'SELECT pg_is_in_recovery();'

bash scripts/compose-stage.sh 17 exec -T postgres-primary \
  psql -U labadmin -d labdb -Atqc \
  "SELECT client_addr || ' ' || state FROM pg_stat_replication;"
```

**Observe:** The replica query returns `t`. The primary reports the replica
client and `streaming`. The script inserts `script-replication-test` on the
primary, waits for it, prints `Replica received: ...`, and ends with:

```text
Replication checks passed.
```

**Explain:** The primary's `db_a` address is `10.10.21.20`; the standby's
address is `10.10.22.20`. The replica entrypoint installs the `db_b` to `db_a`
route, and the router firewall allows the replica's TCP `5432` replication
traffic. PostgreSQL then authenticates the `replicator` connection and replays
WAL.

The shell quoting in the direct state query is important. The outer shell
quotes are double quotes so the SQL string can contain single quotes, as in the
repository script.

```bash
bash scripts/compose-stage.sh 17 exec -T postgres-primary \
  psql -U labadmin -d labdb -Atqc \
  "SELECT client_addr || ' ' || state FROM pg_stat_replication;"
```

### 6. Collect Cross-Layer Evidence

**Predict:** If all four scripts pass, which independent observations should
also be visible at the route, firewall, listener, proxy, and database layers?

**Run:**

```bash
bash scripts/compose-stage.sh 17 exec -T app-a-test ip neigh

bash scripts/compose-stage.sh 17 exec -T lab-router \
  tcpdump -ni any -c 8 'host 10.10.21.20 and tcp port 5432'

bash scripts/compose-stage.sh 17 exec -T nginx-a ss -lnt

bash scripts/compose-stage.sh 17 exec -T postgres-primary ss -lnt

bash scripts/compose-stage.sh 17 exec -T lab-router \
  iptables -L FORWARD -n -v --line-numbers

bash scripts/compose-stage.sh 17 exec -T nat-gateway \
  iptables -t nat -L POSTROUTING -n -v
```

Run the `tcpdump` command in one terminal while running
`bash scripts/test-routing.sh` in another.

**Observe:** The capture should show TCP traffic involving
`10.10.21.20:5432`. The neighbor table may contain learned MAC addresses for
local next hops. Nginx listens on port 80, PostgreSQL listens on port 5432, the
router has matching `FORWARD` rules, and the NAT gateway has matching
`MASQUERADE` rules.

**Explain:** These checks move from an application symptom toward the first
kernel decision that could explain it. Counters and listeners are evidence;
they are not substitutes for checking the route and return path.

## Expected Observations

The final paths are:

```text
public-a-test -> nginx-a:80
             -> lab-router -> app-a-test:8000

app-a-test -> lab-router -> postgres-primary:5432
           <- return route through 10.10.21.2

app-a-test -> nat-gateway 10.10.11.3
           -> MASQUERADE -> nat-public-test:8080

postgres-replica -> lab-router -> postgres-primary:5432
                 -> WAL replay on db_b
```

The four script endings are the simplest pass evidence:

| Check | Pass evidence | Main failure layers |
|---|---|---|
| Routing | `Routing checks passed.` | route, next hop, listener, return route |
| Firewall | `Firewall checks passed.` | `FORWARD`, allowed port, proxy path |
| NAT | `NAT checks passed.` | default route, egress route, MASQUERADE |
| Replication | `Replication checks passed.` | route, firewall, `pg_hba.conf`, WAL |

If a script exits nonzero, treat the first failed command as the observation.
Do not infer that later layers are broken until the earlier layer has passed.

## Checkpoint: Definition of Done

- [ ] The final stack starts with
      `bash scripts/compose-stage.sh 17 up -d --build --wait`.
- [ ] `bash scripts/test-routing.sh` exits 0 and prints
      `Routing checks passed.`
- [ ] `bash scripts/test-firewall.sh` exits 0 and prints
      `Firewall checks passed.`
- [ ] `bash scripts/test-nat.sh` exits 0 and prints
      `NAT checks passed.`
- [ ] `bash scripts/test-replication.sh` exits 0 and prints
      `Replication checks passed.`
- [ ] The expected denied public-to-app path is still denied.
- [ ] You can name the first observation to make for a route, firewall, NAT,
      listener, or replication failure.

## Break It: Remove the App-to-Database Route

This is one controlled failure. It changes one runtime route in
`app-a-test`; it does not edit Compose, stop PostgreSQL, or delete a volume.

**Predict:** After deleting the specific route to `db_a`, what next hop will
`app-a-test` select for `10.10.21.20`? Will the routing checkpoint pass?

**Run:**

```bash
bash scripts/compose-stage.sh 17 exec -T app-a-test \
  ip route delete 10.10.21.0/24 via 10.10.11.2

bash scripts/compose-stage.sh 17 exec -T app-a-test \
  ip route get 10.10.21.20
```

Now run the real checkpoint while converting its nonzero status into visible
expected-failure evidence:

```bash
if bash scripts/test-routing.sh; then
  printf 'Unexpected pass: the route failure was not observed.\n'
else
  printf 'Expected failure: routing checkpoint stopped at the broken path.\n'
fi
```

**Observe:** `ip route get` no longer selects `10.10.11.2`. It may select the
NAT default route or show another route decision, and the TCP check should not
complete. The router, firewall, and primary are still running.

**Explain:** The first broken layer is the source endpoint's route selection.
The packet never takes the intended app-to-database path, so inspecting
PostgreSQL authentication first would be a category error.

**Recover:** Recreate only the endpoint. Its Compose command reapplies all
static routes and restarts the app HTTP server:

```bash
bash scripts/compose-stage.sh 17 up -d --force-recreate --wait app-a-test

bash scripts/test-routing.sh
bash scripts/test-firewall.sh
bash scripts/test-nat.sh
bash scripts/test-replication.sh
```

All four scripts should pass again. Do not start another failure experiment
until this complete baseline is restored.

## Failure Matrix

Use this table after a failed checkpoint. It is a diagnostic map, not a list
of additional break exercises.

| Symptom | First evidence | Likely first layer | Recovery or next check |
|---|---|---|---|
| `ip route get` uses Docker or NAT gateway instead of the lab router | `bash scripts/compose-stage.sh 17 exec -T app-a-test ip route get 10.10.21.20` | endpoint route | recreate the affected endpoint; inspect its startup command |
| Route is correct but TCP times out | `bash scripts/compose-stage.sh 17 exec -T lab-router iptables -L FORWARD -n -v` | forwarding or firewall | inspect router policy, allow rule, and return route |
| TCP is refused | `bash scripts/compose-stage.sh 17 exec -T postgres-primary ss -lnt` | destination listener | inspect service health and logs; a refusal is not a route timeout |
| Nginx public request times out | `bash scripts/compose-stage.sh 17 exec -T nginx-a ss -lnt` and router `FORWARD` counters | proxy route or firewall | inspect Nginx's upstream route and the public-to-app TCP rule |
| No packets appear in the router capture | `bash scripts/compose-stage.sh 17 exec -T lab-router tcpdump -ni any -c 8 'host 10.10.21.20 and tcp port 5432'` | source route or earlier dependency | inspect `ip route get`, then the local neighbor table |
| NAT request fails but private routing passes | `bash scripts/compose-stage.sh 17 exec -T nat-gateway ip route` and `bash scripts/compose-stage.sh 17 exec -T nat-gateway iptables -t nat -L POSTROUTING -n -v` | default route or translation | check `10.10.30.1` egress and MASQUERADE counters |
| Replica is healthy but no new row arrives | `bash scripts/compose-stage.sh 17 exec -T postgres-primary psql -U labadmin -d labdb -c 'SELECT client_addr, state FROM pg_stat_replication;'` | WAL connection, route, or firewall | check `state`, the db_b route, TCP 5432, then `.pgpass` and `pg_hba.conf` |
| TCP works but PostgreSQL rejects the session | `psql` error after `nc` succeeds | PostgreSQL authentication | inspect the relevant `pg_hba.conf` rule and lab credentials |
| Name fails while a known IP works | `getent hosts` plus the known-IP request | Docker DNS or service attachment | inspect `/etc/resolv.conf` and shared network membership |

## Cloud Mapping

These correspondences are useful for reasoning about responsibilities, but
they are not claims of managed cloud behavior:

| Lab component | Cloud-style analogy | Boundary to remember |
|---|---|---|
| Docker bridge subnet | VPC subnet | A bridge is a local Docker Layer-2 network, not a cloud VPC |
| `lab-router` | routing fabric or transit router | This is a Linux container with manually configured routes |
| router `iptables` `FORWARD` rules | stateful network filtering | Rule semantics and lifecycle are not identical to a cloud security group |
| `nat-gateway` and MASQUERADE | managed NAT Gateway | Here the learner owns interfaces, routes, rules, and process lifecycle |
| `nginx-a` and `nginx-b` | public reverse-proxy or load-balancing tier | Nginx creates separate client and upstream TCP sessions |
| `postgres-replica` | cross-zone or cross-region standby | This lab demonstrates physical streaming, not automatic failover |
| `postgres_replica_data` | persistent database storage | A named Docker volume is local lab storage, not a replicated storage service |

## Clean Up

Remove the final stack while preserving the primary and replica volumes:

```bash
bash scripts/compose-stage.sh 17 down
```

For an intentional full database reset only, remove the volumes explicitly:

```bash
bash scripts/compose-stage.sh 17 down -v
```

The second command erases `postgres_primary_data` and
`postgres_replica_data`. Use it only when you want the next startup to run
primary initialization and replica bootstrap from empty data directories.

## Conclusion and Next Chapter

The capstone made the complete packet and database paths observable, proved
the expected pass and deny behavior with the repository scripts, and showed
how to isolate a failure at the first broken layer. The Docker lab is now a
finished course environment.

There is no required next chapter. Re-run chapters 15 through 17 with a clean
volume when you want to practice manual replication, automated persistence,
and final failure diagnosis again.
