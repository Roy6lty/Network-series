# Chapter 09: Private Networks

![Chapter 09 private Docker networks](diagram.svg)

## Key Concepts

### Docker `internal: true`

Docker user-defined bridge networks normally provide a path from an attached
container toward the Docker host. Setting:

```yaml
internal: true
```

marks the network as internal. Docker does not provide the normal external
egress path from that bridge. This is a boundary at the Docker network layer,
not a replacement for routing or firewall rules.

### Private Does Not Mean Invisible

An internal network can still contain multiple attached containers. It is not
encryption, and it does not prevent all traffic from every container. In this
lab, `lab-router` is explicitly attached to the internal application and
database networks, so it can still route between them when:

```text
the source has a route
        +
the router has a connected route and forwarding enabled
        +
the firewall permits the flow
```

### Three Separate Controls

Keep these controls separate in your reasoning:

```text
Docker internal network = normal host/external egress boundary
route table             = where a packet is sent next
iptables FORWARD        = whether a routed packet may cross the router
```

Changing one does not automatically change the others. A private network can
still have a route, and a route can still be rejected by the firewall.

## Goal

Make the application and database Docker networks private at the bridge layer
while retaining explicit routed access through `lab-router`. By the end, you
should be able to:

- verify which Docker networks are marked internal;
- distinguish an internal bridge from a firewall rule;
- show that application traffic can still use an explicit lab route when the
  firewall permits it;
- explain why application egress does not work before a NAT gateway exists;
- recover a deliberately removed route by recreating the endpoint.

## Progression From Chapter 08

Chapter 08 put a default-deny `iptables` policy on `lab-router`. It controls
forwarded packets after a route sends them toward the router.

Chapter 09 leaves the firewall and the six static endpoint routes in place,
then changes the Docker bridge definition for four networks:

```text
Chapter 08: route exists, firewall decides forwarded traffic
        |
        v
Chapter 09: app and database bridges also block normal Docker host egress
```

The router remains the explicit path between lab subnets. The private bridge
setting does not add NAT, so it does not yet provide external egress.

## What This Stage Adds

The Compose overlay sets `internal: true` on:

```text
app_a  10.10.11.0/24
app_b  10.10.12.0/24
db_a   10.10.21.0/24
db_b   10.10.22.0/24
```

The `public_a` and `public_b` networks remain normal bridge networks. No
service is added, and `nat_public` does not exist yet.

The existing services remain:

```text
public-a-test   10.10.1.10
public-b-test   10.10.2.10
app-a-test      10.10.11.10
app-b-test      10.10.12.10
db-a-test       10.10.21.10
db-b-test       10.10.22.10
lab-router      .2 on every lab subnet
```

## Progress Checklist

- [ ] Start the cumulative Chapter 09 lab.
- [ ] Verify `internal=true` for `app_a`, `app_b`, `db_a`, and `db_b`.
- [ ] Confirm that `app-a-test` still routes lab traffic via `10.10.11.2`.
- [ ] Show that internal database traffic reaches the firewall path.
- [ ] Show that no useful direct external egress exists yet.
- [ ] Remove one route, observe the failure, and recover by recreating the app.

## Before You Begin: Terminal Roles

Run commands from the repository root. Use two terminals when comparing route
inspection and connection behavior:

- **Terminal A** inspects Docker networks and `lab-router`.
- **Terminal B** runs route and connection commands from `app-a-test`.

Chapter 09 still has no HTTP server on the app endpoints and no PostgreSQL
server. A permitted TCP connection to an unused port may therefore end with
`Connection refused`; that is useful evidence that the packet reached the
destination rather than being silently dropped.

### Runtime Preflight

Run the Chapter 08 router preflight before using the private-path tasks. Confirm
that the router is running and forwarding is enabled:

```bash
bash scripts/compose-stage.sh 09 exec lab-router \
  sysctl net.ipv4.ip_forward
```

The value should be `net.ipv4.ip_forward = 1`. If the router is stopped, inspect
its logs before continuing; a stopped router is not an expected effect of
`internal: true`.

## Tasks

### Task 1: Start the Private-Network Stage

**Predict.** The service count should remain seven. The change should appear in
the network metadata, not as a new container.

**Run.** From the repository root:

```bash
bash scripts/compose-stage.sh 09 up -d --build
bash scripts/compose-stage.sh 09 ps
```

**Observe.** Confirm that the six endpoint services and `lab-router` are
running. Then ask Compose to show the resolved model:

```bash
bash scripts/compose-stage.sh 09 config
```

Find `networks` and the four `internal: true` entries. The exact order of the
resolved YAML is not important.

**Explain.** Chapter 09 is a network-definition change. The containers keep
their names, addresses, routes, and capabilities from earlier chapters.

### Task 2: Verify the Docker Network Boundary

**Predict.** `app_a`, `app_b`, `db_a`, and `db_b` should report `internal=true`.
The two public networks should not.

**Run.** In Terminal A:

```bash
for network in app_a app_b db_a db_b; do
  docker network inspect "docker-subnet_${network}" \
    --format '{{.Name}} internal={{.Internal}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
done
docker network inspect docker-subnet_public_a \
  --format '{{.Name}} internal={{.Internal}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

The runner uses the repository directory name as its Compose project name, so
the network names are `docker-subnet_app_a`, `docker-subnet_db_a`, and so on.

**Observe.** The important fields should look like:

```text
docker-subnet_app_a internal=true subnet=10.10.11.0/24
docker-subnet_app_b internal=true subnet=10.10.12.0/24
docker-subnet_db_a internal=true subnet=10.10.21.0/24
docker-subnet_db_b internal=true subnet=10.10.22.0/24
docker-subnet_public_a internal=false subnet=10.10.1.0/24
```

**Explain.** `internal=true` changes the bridge's normal external attachment.
It does not remove the bridge, its IP subnet, or the explicitly attached
`lab-router` interface.

### Task 3: Compare Local, Routed, and External Destinations

**Predict.** The Chapter 06 route to another lab subnet should still use
`lab-router` at `10.10.11.2`. A destination outside the lab has no NAT gateway
next hop yet and therefore has no useful external path.

**Run.** In Terminal B:

```bash
bash scripts/compose-stage.sh 09 exec app-a-test ip route
bash scripts/compose-stage.sh 09 exec app-a-test \
  ip route get 10.10.21.10
bash scripts/compose-stage.sh 09 exec app-a-test \
  ip route get 8.8.8.8
```

**Observe.** The database destination should use a route similar to:

```text
10.10.21.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

The external lookup may show Docker's `10.10.11.1` default gateway or report
that the network is unreachable, depending on Docker and kernel behavior. The
important result is that it does not select a NAT gateway; Chapter 10 has not
added one.

**Explain.** A route lookup reports a kernel decision, not a guarantee of
end-to-end reachability. The private bridge can still have a local gateway
entry while Docker prevents that bridge from providing normal external egress.

### Task 4: Test an Explicit Private Path and External Egress

**Predict.** The firewall rule for `app_a -> db_a TCP 5432` should permit the
connection to cross `lab-router`. `db-a-test` has no PostgreSQL listener yet,
so expect `Connection refused`, not a successful database session. An
external request should fail because neither a NAT gateway nor an external
service is present.

**Run.** First test the permitted application-to-database path:

```bash
bash scripts/compose-stage.sh 09 exec -T app-a-test \
  nc -vz -w 3 10.10.21.10 5432
```

Now try a reserved documentation address so the test does not depend on an
actual public Internet service:

```bash
bash scripts/compose-stage.sh 09 exec -T app-a-test \
  curl --silent --show-error --connect-timeout 2 \
  http://198.51.100.10:8080
```

**Observe.** The database test should normally report `Connection refused`.
The external curl should fail or time out. Do not interpret a route through
`10.10.11.1` as working external egress. Inspect the router policy if the
database test times out instead of being refused:

```bash
bash scripts/compose-stage.sh 09 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

**Explain.** The first test crossed an internal `app_a` bridge, reached the
router, matched the Chapter 08 database allow rule, and reached `db-a-test`.
The second test has no useful Docker egress path. The private network boundary
and the router firewall are both involved, but they answer different
questions.

### Task 5: Confirm the Router Is Still Explicitly Attached

**Predict.** Marking a network internal should not detach `lab-router`. The
router should still have addresses on the app and database subnets.

**Run.** In Terminal A:

```bash
bash scripts/compose-stage.sh 09 exec lab-router ip -o -4 addr show
bash scripts/compose-stage.sh 09 exec lab-router ip route
```

**Observe.** Find these router addresses and connected routes:

```text
10.10.11.2/24 and 10.10.11.0/24
10.10.12.2/24 and 10.10.12.0/24
10.10.21.2/24 and 10.10.21.0/24
10.10.22.2/24 and 10.10.22.0/24
```

Also confirm forwarding remains enabled:

```bash
bash scripts/compose-stage.sh 09 exec lab-router \
  sysctl net.ipv4.ip_forward
```

The value should be `net.ipv4.ip_forward = 1`.

**Explain.** The router is an intentional attachment to each private zone.
This is why internal networks can still participate in explicitly routed lab
traffic. External egress needs a different design, which Chapter 10 supplies.

## Expected Observations

The expected state is:

```text
app_a, app_b, db_a, db_b: internal=true
public_a, public_b:       internal=false
app-a-test -> db_a:       route via 10.10.11.2; firewall permits TCP 5432
app-a-test -> external:   no useful direct egress path
nat-gateway:              not present yet
```

The `nc` result against `10.10.21.10:5432` is a useful distinction:

```text
Connection refused = the packet reached db-a-test, but no service listens
Timeout             = inspect the route and FORWARD policy
```

The private-network change is successful when the four network objects report
`internal=true` while the router's private interfaces and connected routes are
still present.

## Break It: Remove One Private Route

This exercise changes only runtime state inside `app-a-test`; it does not edit
Compose files or Docker network metadata.

**Predict.** If the specific route to `db_a` is removed, `app-a-test` will no
longer select `10.10.11.2` for `10.10.21.10`. The permitted private connection
should fail or use an unusable Docker default path.

**Run.** In Terminal B:

```bash
bash scripts/compose-stage.sh 09 exec app-a-test \
  ip route delete 10.10.21.0/24 via 10.10.11.2
bash scripts/compose-stage.sh 09 exec app-a-test \
  ip route get 10.10.21.10
bash scripts/compose-stage.sh 09 exec -T app-a-test \
  nc -vz -w 3 10.10.21.10 5432
```

**Observe.** The route lookup should no longer contain `via 10.10.11.2` for
this destination. The connection should fail; the router and network's
`internal=true` setting have not changed.

**Explain.** A private boundary does not manufacture a route. The failure was
introduced at the source endpoint before the packet could use the intended
router interface.

**Recovery.** Recreate `app-a-test`. Its Chapter 06 startup command runs again
and reinstalls the static routes:

```bash
bash scripts/compose-stage.sh 09 up -d --force-recreate app-a-test
bash scripts/compose-stage.sh 09 exec app-a-test \
  ip route get 10.10.21.10
bash scripts/compose-stage.sh 09 exec -T app-a-test \
  nc -vz -w 3 10.10.21.10 5432
```

The route lookup should again use `10.10.11.2`. The final connection should
again reach `db-a-test` and normally report `Connection refused` because no
database service exists yet.

## Checkpoint: Definition of Done

You are ready for Chapter 10 when all of these are true:

- the four app/database networks report `internal=true`;
- the public networks remain normal bridges;
- `app-a-test` selects `10.10.11.2` for the `db_a` subnet;
- the app-to-database test reaches `db-a-test` but finds no listener;
- the external egress test fails before NAT is introduced;
- `lab-router` still has private interfaces and `ip_forward = 1`;
- deleting the source route breaks the path and recreating `app-a-test` restores
  it.

Mark the matching items in the progress checklist above as you complete them.

## Clean Up

Remove the cumulative resources before moving to the NAT stage:

```bash
bash scripts/compose-stage.sh 09 down
```

## Conclusion / Next Chapter

The application and database bridges are now private at the Docker network
boundary, while explicit routing through `lab-router` still works when the
firewall permits it. Private does not mean disconnected; it means the normal
external path is no longer supplied by Docker.

Chapter 10 adds `nat-gateway` on `app_a`, `app_b`, and `nat_public`. App default
routes will point to that gateway, which will use `MASQUERADE` to provide
controlled private egress.
