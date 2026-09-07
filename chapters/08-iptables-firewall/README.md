# Chapter 08: Stateful Firewalling

![Chapter 08 stateful firewall](diagram.svg)

## Key Concepts

### The `FORWARD` Chain

Chapter 07 showed packets crossing `lab-router`. This chapter puts a policy
decision in that path. The router's `FORWARD` chain evaluates packets that are
being routed between interfaces:

```text
public_a -> lab-router -> app_a
                         ^
                    FORWARD chain
```

This is different from `INPUT`, which evaluates traffic addressed to the
router itself. A ping to a router interface is not the same test as traffic
that the router forwards to another container.

### Default Deny

The router sets:

```text
FORWARD policy = DROP
```

The rules then explicitly allow the flows required by the application design.
When no rule matches, the policy drops the packet. Rule order matters because
iptables evaluates rules from top to bottom.

### Conntrack and Stateful Return Traffic

Linux connection tracking records flow state. The first packet of a TCP
connection is `NEW`. Reply packets are normally `ESTABLISHED`.

The first rule in this lab is:

```text
-m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

This lets reply packets return without writing a separate reverse-direction
rule for every allowed connection. It does not allow a new connection in the
opposite direction.

### Firewalling Is Not Database Authentication

iptables decides whether a packet may cross the router. PostgreSQL's
`pg_hba.conf` decides whether a database session is accepted after a packet
reaches PostgreSQL. They are separate controls.

At this stage the later HTTP and PostgreSQL services do not exist yet. A
connection to an allowed port can therefore end with `Connection refused`
because the route and firewall allowed it but no process is listening.

## Goal

Replace unrestricted inter-subnet forwarding with a default-deny policy on
`lab-router`. By the end, you should be able to:

- inspect the `FORWARD` policy and rule order;
- distinguish forwarded traffic from traffic addressed to the router;
- identify the permitted source, destination, protocol, and port combinations;
- explain why `ESTABLISHED,RELATED` covers return packets;
- distinguish a firewall timeout from a reachable host with no listener;
- restore the firewall after a deliberate rule-flush experiment.

## Progression From Chapter 07

Chapter 07 observed a working path from `public-a-test` to `app-b-test`:

```text
public-a-test -> lab-router -> app-b-test
```

Chapter 08 keeps the same six networks, routes, and multi-homed router. It
replaces the router image with `docker-networking-vpc-lab/lab-router:firewall`
and runs `chapters/08-iptables-firewall/router/entrypoint.sh` before the router
command.

The progression is:

```text
Chapter 07: packets can cross the router
        |
        v
Chapter 08: only policy-approved forwarded packets can cross
```

## What This Stage Adds

No endpoint or network is added. The `lab-router` service is rebuilt with
`iproute2`, `iptables`, and `tcpdump`, then its entrypoint:

1. enables `net.ipv4.ip_forward`;
2. flushes old filter and NAT rules;
3. sets `FORWARD` to `DROP`;
4. accepts `ESTABLISHED,RELATED` traffic;
5. accepts the new flows below.

The explicit new-flow rules are:

```text
public_a 10.10.1.0/24  -> app_a 10.10.11.0/24  TCP 8000
public_b 10.10.2.0/24  -> app_b 10.10.12.0/24  TCP 8000
app_a    10.10.11.0/24 -> db_a  10.10.21.0/24  TCP 5432
app_b    10.10.12.0/24 -> db_a  10.10.21.0/24  TCP 5432
db_b     10.10.22.0/24 -> db_a  10.10.21.0/24  TCP 5432
```

ICMP is not an allow rule in this stage. The Chapter 06 static routes still
exist, but a route does not override a firewall policy.

## Progress Checklist

- [ ] Start the cumulative Chapter 08 lab.
- [ ] Confirm that `FORWARD` has a default policy of `DROP`.
- [ ] Identify the `ESTABLISHED,RELATED` rule and five new-flow rules.
- [ ] Show an allowed TCP path and a blocked TCP path.
- [ ] Explain `Connection refused` versus a timeout.
- [ ] Flush the rules once and recover by recreating `lab-router`.

## Before You Begin: Terminal Roles

Run commands from the repository root. Use two terminals when a request and a
router observation are needed:

- **Terminal A** runs inspection commands on `lab-router`.
- **Terminal B** generates TCP traffic from an endpoint.

The stage has seven services. It does not yet include `nginx-a`, `nginx-b`,
`postgres-primary`, or `postgres-replica`; those arrive in later chapters.

### Runtime Preflight

The intended checkpoint requires `lab-router` to remain running. Compose
configures `net.ipv4.ip_forward` while creating the container. The Chapter 08
entrypoint also attempts the write, but tolerates a read-only `/proc/sys` mount
when the value is already `1`:

```text
net.ipv4.ip_forward = 1
```

If `lab-router` exits, inspect its logs and confirm that forwarding is enabled
before continuing. A stopped router is an environment or startup failure; it is
not evidence that the firewall rules rejected traffic.

## Tasks

### Task 1: Start the Firewall Stage

**Predict.** The topology should still contain the six endpoint containers and
`lab-router`. Only the router image and startup behavior should change.

**Run.** From the repository root:

```bash
bash scripts/compose-stage.sh 08 up -d --build
bash scripts/compose-stage.sh 08 ps
```

**Observe.** Confirm that these services are running:

```text
public-a-test
public-b-test
app-a-test
app-b-test
db-a-test
db-b-test
lab-router
```

**Explain.** The firewall is placed on the existing forwarding node. No client
route needs to change for the policy to take effect.

### Task 2: Inspect the Policy and Rule Order

**Predict.** The first rule should accept established return traffic, the next
rules should allow only the five listed new-flow patterns, and unmatched
forwarded packets should be dropped.

**Run.** In Terminal A:

```bash
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -S FORWARD
```

**Observe.** The `iptables -S FORWARD` output should include:

```text
-P FORWARD DROP
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

It should also include the exact source/destination subnets and ports from the
allow list. In the `-L` output, watch the packet and byte counters; they start
at zero or increase as the lab is used.

**Explain.** A static route selects a next hop. The `FORWARD` chain then decides
whether the packet may cross the router. Both decisions must permit the flow.

### Task 3: Prove That ICMP Is Now Blocked

**Predict.** The Chapter 07 ping crosses the router, but ICMP is not one of
the explicit allow rules. Predict that it will time out.

**Run.** In Terminal B:

```bash
bash scripts/compose-stage.sh 08 exec app-a-test \
  ping -c 2 10.10.12.10
```

**Observe.** Expect `100% packet loss` or an equivalent timeout. Inspect the
router counters again:

```bash
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

The default policy or its counter accounts for the unmatched ICMP packets.

**Explain.** This is a policy change, not a routing failure. The endpoint still
has the Chapter 06 route via `10.10.11.2`; the firewall refuses the forwarded
protocol after routing selects the path.

### Task 4: Compare an Allowed Port With a Blocked Port

**Predict.** A new TCP connection from `public-a-test` to `app-a-test` on port
`8000` matches an allow rule. The same source to `app-b-test` on port `8000`
does not match and should time out.

At Chapter 08, neither app endpoint has a server listening on port `8000`, so
first expect a refusal for the allowed path. To make the allowed path visibly
successful, start a temporary HTTP listener in `app-a-test`.

**Run.** In Terminal A, start the temporary listener:

```bash
bash scripts/compose-stage.sh 08 exec -T app-a-test \
  sh -c 'python3 -m http.server 8000 --bind 0.0.0.0 >/tmp/ch08-http.log 2>&1 & echo $! >/tmp/ch08-http.pid'
```

Wait one second, then in Terminal B test the allowed path:

```bash
bash scripts/compose-stage.sh 08 exec -T public-a-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.11.10:8000
```

Now test the blocked source/destination pair:

```bash
bash scripts/compose-stage.sh 08 exec -T public-a-test \
  curl --silent --show-error --connect-timeout 2 \
  http://10.10.12.10:8000
```

**Observe.** The first request should print the Python directory-listing HTML.
The second should fail with a timeout or another connection error after about
two seconds. It should not print an HTTP response from `app-b-test`.

Inspect counters after both requests:

```bash
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

**Explain.** The first TCP connection reached a listener because its new flow
matched:

```text
10.10.1.0/24 -> 10.10.11.0/24 TCP dport 8000
```

Its return packets matched `ESTABLISHED,RELATED`. The second flow was routed
toward `app_b`, but no allow rule matched it, so the default policy dropped it.

If you skip the temporary listener, an allowed path to an unused port should
report `Connection refused`. That means the host was reached and rejected the
connection because no process was listening. A timeout is evidence of a drop
or an unreachable path, not proof that the application rejected the request.

### Task 5: Read the Stateful Rule Counters

**Predict.** A single `curl` causes several packets in each direction. The
specific new-flow rule should count the new connection, and the
`ESTABLISHED,RELATED` rule should count return traffic.

**Run.** Make one more allowed request, then inspect the counters immediately:

```bash
bash scripts/compose-stage.sh 08 exec -T public-a-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.11.10:8000 >/dev/null
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

**Observe.** Counters on the public-A-to-app-A rule and the
`ESTABLISHED,RELATED` rule should increase. Exact counts vary because TCP
setup, HTTP, and teardown may produce different numbers of packets.

**Explain.** The state match is not an unrestricted allow. It accepts packets
that conntrack associates with an already permitted flow, which is why one
return rule can cover replies for all the allowed directions.

## Expected Observations

The important evidence for this stage is:

```text
FORWARD policy: DROP
allowed new flow: public_a -> app_a TCP 8000
blocked new flow: public_a -> app_b TCP 8000
return traffic: accepted by ESTABLISHED,RELATED
ICMP across router: dropped because no ICMP allow rule exists
```

Keep this distinction in mind:

```text
Connection refused = packet reached a host with no listener
Timeout           = packet was dropped or no response returned
```

Rule counters are stronger evidence than a timeout alone. Read the matching
rule and its counter before changing routes or services.

## Break It: Flush the Forward Rules

Leave the temporary HTTP listener running for this exercise. This intentionally
removes the allow rules while preserving the default policy of `DROP`.

**Predict.** The listener is healthy, but a request from `public-a-test` to
`app-a-test` should now time out because the explicit allow rule is gone.

**Run.** In Terminal A:

```bash
bash scripts/compose-stage.sh 08 exec lab-router iptables -F FORWARD
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

In Terminal B:

```bash
bash scripts/compose-stage.sh 08 exec -T public-a-test \
  curl --silent --show-error --connect-timeout 2 \
  http://10.10.11.10:8000
```

**Observe.** The chain is empty apart from its default policy, and the request
times out even though `app-a-test` still has a listening HTTP process.

**Explain.** The failure is at the router's policy boundary. The endpoint,
route, and listener did not change.

**Recovery.** Recreate only `lab-router`. Its entrypoint rebuilds the intended
policy:

```bash
bash scripts/compose-stage.sh 08 up -d --force-recreate lab-router
bash scripts/compose-stage.sh 08 exec lab-router iptables -S FORWARD
bash scripts/compose-stage.sh 08 exec -T public-a-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.11.10:8000 >/dev/null
```

The final command should succeed again. Stop the temporary listener:

```bash
bash scripts/compose-stage.sh 08 exec -T app-a-test \
  sh -c 'kill "$(cat /tmp/ch08-http.pid)"'
```

## Checkpoint: Definition of Done

You are ready for Chapter 09 when you can verify all of the following:

- `iptables -S FORWARD` reports `-P FORWARD DROP`;
- the five intended new TCP flow rules are present;
- an allowed `public_a` to `app_a` request reaches a listener;
- an unallowed `public_a` to `app_b` request times out;
- `ESTABLISHED,RELATED` counters increase for return traffic;
- flushing the chain breaks the allowed request;
- recreating `lab-router` restores the policy and the request works again.

Mark the matching items in the progress checklist above as you complete them.

## Clean Up

If the temporary listener is still running, stop it first:

```bash
bash scripts/compose-stage.sh 08 exec -T app-a-test \
  sh -c 'test ! -f /tmp/ch08-http.pid || kill "$(cat /tmp/ch08-http.pid)"'
```

Then remove the cumulative resources:

```bash
bash scripts/compose-stage.sh 08 down
```

## Conclusion / Next Chapter

You turned an observed routed path into a policy-controlled path. The router
now permits only the designed TCP flows and accepts their stateful replies.

Chapter 09 marks the application and database Docker networks as
`internal: true`. That adds a Docker bridge egress boundary; it does not
replace the router's routes or its firewall policy.
