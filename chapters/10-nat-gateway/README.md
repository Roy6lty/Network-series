# Chapter 10: NAT Gateway

![Chapter 10 NAT gateway and MASQUERADE](diagram.svg)

## Key Concepts

### Default Routes

A default route is the catch-all route used when no more-specific route
matches. Chapter 06 installed specific routes from the endpoint containers to
the other lab subnets. Chapter 10 keeps those routes and replaces the app
default route with a route through `nat-gateway`.

For `app-a-test`:

```text
10.10.21.0/24 -> lab-router at 10.10.11.2
everything else -> nat-gateway at 10.10.11.3
```

The specific database route still wins over the default route.

### What Is a NAT Gateway?

`nat-gateway` is a multi-homed Linux container. It has one interface in each
application network and one interface in `nat_public`:

```text
app_a      10.10.11.3
app_b      10.10.12.3
nat_public 10.10.30.2
```

It has IPv4 forwarding enabled and uses conntrack to remember translations.
The gateway receives private traffic on an app interface, forwards it toward
`nat_public`, and rewrites the source address on the public-facing interface.

### MASQUERADE

The NAT entrypoint installs these rules:

```text
10.10.11.0/24 -> MASQUERADE when leaving nat_public
10.10.12.0/24 -> MASQUERADE when leaving nat_public
```

For an app request such as:

```text
before: 10.10.11.10:40000 -> 10.10.30.10:8080
after:  10.10.30.2:40000  -> 10.10.30.10:8080
```

the actual source port may vary. MASQUERADE uses the current address of the
egress interface. `SNAT` is the alternative when an explicit source address is
preferred.

NAT changes addresses after route selection chooses an egress interface. It
does not choose the route, and it is not a substitute for a firewall.

## Goal

Separate routing from address translation and provide controlled egress for
the private application networks. By the end, you should be able to:

- identify the three `nat-gateway` interfaces;
- show that app traffic selects the NAT gateway as its default next hop;
- distinguish a specific lab route from the default route;
- observe `MASQUERADE` rule counters increase after an HTTP request;
- verify from server logs that the public-side source is `10.10.30.2`;
- explain why the reply can return to a private app through conntrack;
- recover after removing the gateway's default route.

## Progression From Chapter 09

Chapter 09 marked `app_a`, `app_b`, `db_a`, and `db_b` as `internal: true`.
That removed the normal Docker bridge egress path. The app containers could
still use explicit lab routes through `lab-router`, but they had no controlled
path to an external or public-side network.

Chapter 10 adds a separate egress device:

```text
Chapter 09: private app bridges, no NAT gateway
        |
        v
Chapter 10: app default routes -> nat-gateway -> nat_public
```

The lab router remains responsible for the explicit routes between the six
original subnets. The NAT gateway handles the app default path.

## What This Stage Adds

The Compose overlay adds these services and network changes:

```text
nat-gateway      app_a 10.10.11.3
                 app_b 10.10.12.3
                 nat_public 10.10.30.2

nat-public-test  nat_public 10.10.30.10
                 Python HTTP server on TCP 8080
```

`nat-gateway` uses image
`docker-networking-vpc-lab/nat-gateway:masquerade`, adds `NET_ADMIN` and
`NET_RAW`, and sets `net.ipv4.ip_forward` to `1`. Its entrypoint finds the
interfaces from their IP addresses, installs a default route through
`10.10.30.1`, sets the `FORWARD` policy to `DROP`, permits app-to-public
forwarding plus established replies, and adds the two `POSTROUTING`
`MASQUERADE` rules.

The app command overlays retain their Chapter 06 static routes and add:

```text
app-a-test default via 10.10.11.3
app-b-test default via 10.10.12.3
```

## Progress Checklist

- [ ] Start the cumulative Chapter 10 lab.
- [ ] Confirm the three `nat-gateway` addresses and its connected routes.
- [ ] Confirm IPv4 forwarding and the NAT gateway default route.
- [ ] Show app traffic selecting `10.10.11.3` or `10.10.12.3`.
- [ ] Make an HTTP request to `nat-public-test` through NAT.
- [ ] Observe `POSTROUTING` counters and the translated source in logs.
- [ ] Remove the gateway default route, observe the failure, and recover it.

## Before You Begin: Terminal Roles

Run commands from the repository root. Use two terminals for the main request:

- **Terminal A** inspects `nat-gateway` routes, interfaces, and iptables.
- **Terminal B** runs `curl` from `app-a-test` or `app-b-test`.

The public-side test server is not an Internet service. It is the repository's
`nat-public-test` service at `10.10.30.10:8080`. This gives you a repeatable
destination and a server log that can show the translated source address.

### Runtime Preflight

The NAT network uses the fixed subnet `10.10.30.0/24`. Before starting this
stage, check whether another Docker network already owns an overlapping CIDR:

```bash
docker network inspect $(docker network ls -q) \
  --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

If Docker reports `invalid pool request: Pool overlaps with other one on this
address space`, identify the unrelated stack that owns the overlapping network
and stop or remove only that stack before retrying. Do not remove an unrelated
network just because its name is similar to `nat_public`.

The NAT tasks require `lab-router` to be running because Chapter 10 loads the
earlier firewall stage. Confirm forwarding before continuing:

```bash
bash scripts/compose-stage.sh 10 exec lab-router \
  sysctl net.ipv4.ip_forward
```

The value should be `net.ipv4.ip_forward = 1`. If the router is stopped, inspect
its logs before continuing; a failed `lab-router` is not a NAT rule result.

## Tasks

### Task 1: Start the NAT Stage

**Predict.** Chapter 10 should contain the seven services from the earlier
stages plus `nat-gateway` and `nat-public-test`, for nine services total.

**Run.** From the repository root:

```bash
bash scripts/compose-stage.sh 10 up -d --build
bash scripts/compose-stage.sh 10 ps
bash scripts/compose-stage.sh 10 config --services
```

**Observe.** The service list should include:

```text
public-a-test
public-b-test
app-a-test
app-b-test
db-a-test
db-b-test
lab-router
nat-gateway
nat-public-test
```

`nat-public-test` should be running its Python HTTP server. The exact order in
`ps` is not important.

**Explain.** The two new services add an egress test network and a gateway;
they do not replace `lab-router` or remove the original six networks.

### Task 2: Inspect the NAT Gateway Interfaces and Routes

**Predict.** `nat-gateway` should have one address in each of `app_a`, `app_b`,
and `nat_public`, plus connected routes for all three networks and a default
route through `10.10.30.1`.

**Run.** In Terminal A:

```bash
bash scripts/compose-stage.sh 10 exec nat-gateway ip -o -4 addr show
bash scripts/compose-stage.sh 10 exec nat-gateway ip route
bash scripts/compose-stage.sh 10 exec nat-gateway \
  sysctl net.ipv4.ip_forward
```

**Observe.** Find these values; interface names may be `eth0`, `eth1`, and
`eth2` in a different order:

```text
10.10.11.3/24
10.10.12.3/24
10.10.30.2/24
default via 10.10.30.1
net.ipv4.ip_forward = 1
```

The route table should also contain directly connected routes for:

```text
10.10.11.0/24
10.10.12.0/24
10.10.30.0/24
```

**Explain.** The gateway needs an app-side ingress interface, a public-side
egress interface, and forwarding enabled. The default route is used only when
the destination does not match a more-specific connected or static route.

### Task 3: Inspect Route Selection From `app-a-test`

**Predict.** `app-a-test` should send the public-side test destination to
`10.10.11.3`. It should still send a database-subnet destination to
`lab-router` at `10.10.11.2` because that `/24` route is more specific.

**Run.** In Terminal B:

```bash
bash scripts/compose-stage.sh 10 exec app-a-test ip route
bash scripts/compose-stage.sh 10 exec app-a-test \
  ip route get 10.10.30.10
bash scripts/compose-stage.sh 10 exec app-a-test \
  ip route get 10.10.21.10
```

**Observe.** The public-side lookup should look similar to:

```text
10.10.30.10 via 10.10.11.3 dev eth0 src 10.10.11.10
```

The database lookup should still use:

```text
10.10.21.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

Exact interface and extra kernel fields vary. The important fields are the
next hops: `.11.3` for the NAT path and `.11.2` for the lab-router path.

**Explain.** Routing happens before NAT. The app chooses the next hop and
interface first; only then can `nat-gateway` apply its `POSTROUTING`
translation on the way out of `nat_public`.

### Task 4: Make an HTTP Request Through the Gateway

**Predict.** The request should start with source `10.10.11.10`, enter
`nat-gateway` on `app_a`, leave through `nat_public`, and reach
`nat-public-test` at `10.10.30.10:8080`. The response should return through
conntrack to `app-a-test`.

**Run.** In Terminal B:

```bash
bash scripts/compose-stage.sh 10 exec -T app-a-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.30.10:8080
```

Repeat from the other private application network:

```bash
bash scripts/compose-stage.sh 10 exec -T app-b-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.30.10:8080
```

**Observe.** Each command should print the HTML directory listing returned by
Python's `http.server`. A successful response proves the route, forwarding,
firewall, NAT, and return path all worked for that request.

**Explain.** The destination is on `nat_public`, but the app is on an internal
network. The app did not connect directly to the public-side bridge; it sent to
the next hop configured by the Chapter 10 command overlay.

### Task 5: Observe MASQUERADE Counters and the Translated Source

**Predict.** The `POSTROUTING` rules should contain one MASQUERADE rule for
each app subnet. Their counters should increase after the requests.

**Run.** In Terminal A, inspect the rules before and after one request:

```bash
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v --line-numbers
```

Run this in Terminal B:

```bash
bash scripts/compose-stage.sh 10 exec -T app-a-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.30.10:8080 >/dev/null
```

Then inspect the rules again and read the public-side server log:

```bash
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v --line-numbers
bash scripts/compose-stage.sh 10 logs --tail=5 nat-public-test
```

**Observe.** The rule for source `10.10.11.0/24` should have a larger packet
and byte count after the request. The `nat-public-test` log should show a
client address of `10.10.30.2`, not `10.10.11.10`. Timestamps and exact byte
counts vary.

If the counters stay at zero, return to Task 3. Check the route and selected
interface before changing the iptables rules.

**Explain.** The source rewrite happened at the NAT gateway's public-facing
egress. Conntrack remembers that `10.10.30.2` represents the original private
flow, so the reply can be translated back to `10.10.11.10`.

### Task 6: Inspect the Gateway's Forwarding Policy

**Predict.** The NAT gateway should default to dropping forwarded traffic,
then allow app interfaces to the public interface and established return
traffic back to the apps.

**Run.** In Terminal A:

```bash
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -L FORWARD -n -v --line-numbers
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v --line-numbers
```

**Observe.** Find `policy DROP`, an `ESTABLISHED,RELATED` rule, app-to-public
allow rules, and the two source-subnet MASQUERADE rules. The forward counters
should reflect the HTTP requests.

**Explain.** NAT is not the only requirement. The gateway must route the
packet, permit forwarding, rewrite the source on egress, and retain conntrack
state for the response.

## Expected Observations

The completed data path should be:

```text
app-a-test 10.10.11.10
        |
        | default via 10.10.11.3
        v
nat-gateway 10.10.11.3
        |
        | route to nat_public, MASQUERADE
        v
nat-gateway 10.10.30.2
        |
        v
nat-public-test 10.10.30.10:8080
```

The important before-and-after evidence is:

```text
route lookup:      next hop 10.10.11.3
POSTROUTING rule:  source 10.10.11.0/24 counter increases
server log:        client 10.10.30.2
curl:              HTTP response from nat-public-test
```

For a destination in the original lab, routing remains separate from NAT. For
example, `10.10.21.10` still selects `10.10.11.2` from `app-a-test`; it does
not select the NAT gateway merely because a default route exists.

## Break It: Remove the NAT Gateway Default Route

This is a controlled runtime failure. It removes one route inside
`nat-gateway` and leaves the MASQUERADE rules in place.

Do not use `10.10.30.10` as the break target: that address is directly
connected to `nat-gateway` through `nat_public`, so its connected route does not
need the default route. Use a reserved external address instead.

**Predict.** The app should still select `10.10.11.3`, but `nat-gateway` will
have no route for an external destination. The request should fail before a
packet can reach `POSTROUTING`, so the MASQUERADE counter should not increase.

**Run.** Record the NAT counters, remove the gateway default route, and test
from `app-a-test`:

```bash
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v --line-numbers
bash scripts/compose-stage.sh 10 exec nat-gateway \
  ip route delete default via 10.10.30.1
bash scripts/compose-stage.sh 10 exec nat-gateway ip route
bash scripts/compose-stage.sh 10 exec -T app-a-test \
  curl --silent --show-error --connect-timeout 2 \
  http://198.51.100.10:8080
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v --line-numbers
```

**Observe.** The app still has its default route through `10.10.11.3`, but the
gateway's route table no longer has `default via 10.10.30.1`. The curl should
fail, and the MASQUERADE counter should remain unchanged for this failed
external attempt.

**Explain.** The packet reached the NAT gateway because the app route was
correct. It could not be forwarded toward an external destination because the
gateway had no matching route. NAT cannot repair a missing route.

**Recovery.** Recreate only the gateway. Its entrypoint reinstalls the default
route and the firewall/NAT rules:

```bash
bash scripts/compose-stage.sh 10 up -d --force-recreate nat-gateway
bash scripts/compose-stage.sh 10 exec nat-gateway ip route
bash scripts/compose-stage.sh 10 exec -T app-a-test \
  curl --fail --silent --show-error --connect-timeout 3 \
  http://10.10.30.10:8080 >/dev/null
```

The final request should succeed again. The gateway route and NAT state have
been restored by container startup.

## Checkpoint: Definition of Done

You are ready for Chapter 11 when all of these are true:

- `nat-gateway` has `10.10.11.3`, `10.10.12.3`, and `10.10.30.2`;
- its route table has connected app/public routes and `default via 10.10.30.1`;
- `net.ipv4.ip_forward` is `1`;
- `app-a-test` selects `10.10.11.3` for `10.10.30.10`;
- `app-a-test` still selects `10.10.11.2` for `10.10.21.10`;
- `curl` reaches `nat-public-test` on TCP `8080`;
- `POSTROUTING` counters increase after the request;
- the server log identifies `10.10.30.2` as the client;
- deleting the gateway default route breaks the external test and recreating
  `nat-gateway` restores it.

Mark the matching items in the progress checklist above as you complete them.

The repository's automated NAT helper runs against the final cumulative stage,
not only Chapter 10. After the later chapters are present, its commands are:

```bash
bash scripts/compose-stage.sh 17 up -d --build --wait
bash scripts/test-nat.sh
```

It repeats the app request and gateway route/NAT inspections used here.

## Clean Up

Remove the cumulative Chapter 10 resources:

```bash
bash scripts/compose-stage.sh 10 down
```

## Conclusion / Next Chapter

The private application networks now have a deliberate egress path. Route
selection sends app default traffic to `nat-gateway`, forwarding moves it to
`nat_public`, and MASQUERADE makes the public-side source address routable
while conntrack preserves the return path.

Chapter 11 introduces Docker DNS. You will compare service-name resolution
with the raw IP paths you traced and translated in this chapter.
