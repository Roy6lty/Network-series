# Chapter 06: Static Routing

![Chapter 06 forward and return routes](diagram.svg)

## Goal

Apply the routing model from Chapter 05B to the main six-network lab.

Chapter 05B taught routing one hop at a time across several routers. Chapter 06
returns to the standard public, application, and database topology, where one
multi-homed router is connected directly to all six lab networks.

By the end of this chapter, you should be able to:

- identify the correct next hop for a remote subnet;
- explain why the next hop must be reachable on the sender's local network;
- distinguish Docker's bridge gateway (`.1`) from the lab router (`.2`);
- explain why the router needs no static routes for directly connected lab subnets;
- build and test a forward path and return path manually;
- derive the general routing rule for all six endpoint containers;
- inspect route selection with `ip route get`;
- explain why `ip route replace` is used in the Chapter 06 Compose overlay;
- explain how the Chapter 06 Compose file modifies existing services rather than adding new ones;
- verify routing across public, application, and database networks;
- break one route, diagnose the failure, and recover it.

---

## From Chapter 05B

Chapter 05B used this topology:

```text
shell-1
   |
   v
router-1
   |
   v
router-2
   |
   v
router-3
   |
   v
shell-4
```

No single router knew every network.

That meant each router needed to answer:

```text
For this destination,
which directly reachable router should receive the packet next?
```

Chapter 06 uses the same routing logic, but the topology is simpler.

There is now one router:

```text
lab-router
```

and that router is directly connected to all six lab networks.

So the problem changes from:

```text
Which router should forward the packet next?
```

to:

```text
Which local interface of lab-router should this endpoint use as its next hop?
```

The routing rule is still the same:

```text
the next hop must be directly reachable
from the sender's local network
```

---

# Main Lab Topology

The six Docker networks are:

```text
public_a   10.10.1.0/24
public_b   10.10.2.0/24

app_a      10.10.11.0/24
app_b      10.10.12.0/24

db_a       10.10.21.0/24
db_b       10.10.22.0/24
```

The endpoint containers are:

```text
public-a-test   10.10.1.10
public-b-test   10.10.2.10

app-a-test      10.10.11.10
app-b-test      10.10.12.10

db-a-test       10.10.21.10
db-b-test       10.10.22.10
```

The router is attached to all six networks:

```text
                            lab-router

                    public_a  10.10.1.2
                    public_b  10.10.2.2
                    app_a     10.10.11.2
                    app_b     10.10.12.2
                    db_a      10.10.21.2
                    db_b      10.10.22.2
```

A simplified relationship is:

```text
                     public-a-test
                      10.10.1.10
                           |
                       public_a
                      10.10.1.0/24
                           |
                       10.10.1.2
                           |
                           |
public-b-test ---- 10.10.2.2
                           \
                            \
app-a-test ------ 10.10.11.2 \
                              +----------------+
app-b-test ------ 10.10.12.2--|   lab-router   |
                              | ip_forward = 1 |
db-a-test ------- 10.10.21.2--|                |
                              +----------------+
db-b-test ------- 10.10.22.2 /
```

Another way to think about it:

```text
public_a --------\
public_b ---------\
app_a -------------\
app_b --------------- lab-router
db_a ---------------/
db_b --------------/
```

The important point is that `lab-router` is one container with six interfaces.

---

# Key Concept 1: Connected Routes on the Router

When Linux assigns an IP address and subnet to an interface, Linux automatically
creates a connected route for that subnet.

For example, because `lab-router` has:

```text
10.10.11.2/24
```

on its `app_a` interface, Linux automatically knows:

```text
10.10.11.0/24 is directly connected
```

The router should therefore have connected routes similar to:

```text
10.10.1.0/24   dev <interface> src 10.10.1.2
10.10.2.0/24   dev <interface> src 10.10.2.2
10.10.11.0/24  dev <interface> src 10.10.11.2
10.10.12.0/24  dev <interface> src 10.10.12.2
10.10.21.0/24  dev <interface> src 10.10.21.2
10.10.22.0/24  dev <interface> src 10.10.22.2
```

So:

```text
lab-router does not need static routes
for the six original lab networks
```

because all six are directly connected.

The endpoints are different.

Each endpoint is connected to only one lab subnet, so each endpoint needs help
reaching the other five.

---

# Key Concept 2: Docker Gateway `.1` vs Lab Router `.2`

Docker normally gives each bridge network a gateway address ending in `.1`.

For example:

```text
app_a

Docker bridge gateway = 10.10.11.1
lab-router             = 10.10.11.2
app-a-test             = 10.10.11.10
```

These are not the same device.

```text
10.10.11.1
=
Docker-managed bridge gateway

10.10.11.2
=
our custom lab-router
```

Before Chapter 06, `app-a-test` may have:

```text
default via 10.10.11.1
10.10.11.0/24 dev eth0
```

If Linux does not have a more-specific route for a destination such as
`10.10.12.10`, the default route may be selected:

```text
10.10.12.10
        |
        v
default via 10.10.11.1
```

That does not prove `10.10.12.10` is reachable.

It only proves which route Linux selected.

The lab needs a more-specific route through our router:

```text
10.10.12.0/24 via 10.10.11.2
```

Then `/24` wins over the default `/0`.

---

# Key Concept 3: The Next Hop Must Be Local

Suppose:

```text
source      = app-a-test
source IP   = 10.10.11.10
destination = app-b-test
destination = 10.10.12.10
```

The router has two relevant addresses:

```text
10.10.11.2 on app_a
10.10.12.2 on app_b
```

Which address should `app-a-test` use as its next hop?

```text
A. 10.10.11.2
B. 10.10.12.2
```

Correct:

```text
10.10.11.2
```

Why?

Because `10.10.11.2` is directly reachable from `app-a-test`.

```text
app-a-test
10.10.11.10
      |
      | same subnet
      v
lab-router
10.10.11.2
```

This is valid:

```text
10.10.12.0/24 via 10.10.11.2
```

This is not a valid direct next hop from `app-a-test`:

```text
10.10.12.0/24 via 10.10.12.2
```

because `10.10.12.2` is the router's address on a different subnet.

The general rule is:

```text
destination may be remote

but

next hop must be locally reachable
```

---

# Part 1: Start With the Chapter 05 Baseline

## Task 1: Start Chapter 05

Chapter 05 gives us the six endpoint containers and the multi-homed router, but
it does not yet install the endpoint static routes.

Run:

```bash
bash scripts/compose-stage.sh 05 up -d --build
```

Check the services:

```bash
bash scripts/compose-stage.sh 05 ps
```

You should have:

```text
public-a-test
public-b-test
app-a-test
app-b-test
db-a-test
db-b-test
lab-router
```

---

## Task 2: Inspect the Router

Inspect the router's addresses:

```bash
bash scripts/compose-stage.sh 05 exec lab-router ip -o -4 addr show
```

You should find addresses from all six subnets:

```text
10.10.1.2/24
10.10.2.2/24
10.10.11.2/24
10.10.12.2/24
10.10.21.2/24
10.10.22.2/24
```

Now inspect the router's routes:

```bash
bash scripts/compose-stage.sh 05 exec lab-router ip route
```

You should find connected routes for all six networks.

### Prediction

Does `lab-router` need this command?

```bash
ip route add 10.10.12.0/24 via ...
```

Answer:

```text
No.
```

`10.10.12.0/24` is directly connected to the router because one of the router's
interfaces already belongs to that subnet.

---

## Task 3: Confirm IPv4 Forwarding

Run:

```bash
bash scripts/compose-stage.sh 05 exec lab-router \
  sysctl net.ipv4.ip_forward
```

Expected:

```text
net.ipv4.ip_forward = 1
```

Remember:

```text
multiple interfaces
        !=
forwarding automatically enabled
```

`ip_forward=1` allows the Linux kernel to forward packets received on one
interface out another interface.

---

# Part 2: Inspect an Endpoint Before Static Routing

We will use this first path:

```text
app-a-test
10.10.11.10

        ->

app-b-test
10.10.12.10
```

## Task 4: Inspect `app-a-test`

Run:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test ip route
```

You should see something similar to:

```text
default via 10.10.11.1 dev eth0
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
```

The important routes are:

```text
10.10.11.0/24
=
local network

default via 10.10.11.1
=
Docker bridge gateway
```

There is no specific lab route yet for:

```text
10.10.12.0/24
```

---

## Task 5: Ask Linux What It Would Do

Run:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ip route get 10.10.12.10
```

You should see something similar to:

```text
10.10.12.10 via 10.10.11.1 dev eth0 src 10.10.11.10
```

Meaning:

```text
destination = 10.10.12.10
next hop    = 10.10.11.1
interface   = eth0
source      = 10.10.11.10
```

This is a routing decision.

It is not proof of connectivity.

---

## Task 6: Test the Baseline

Run:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ping -c 2 10.10.12.10
```

The request should fail.

The important distinction is:

```text
lab-router exists
        !=
app-a-test is using lab-router
```

The source still sends unmatched traffic toward Docker's `.1` gateway.

---

# Part 3: Build One Route Manually

Before letting Compose automate all routes, build one route yourself.

This applies what Chapter 05B already taught.

## Task 7: Choose the Source Next Hop

Question:

```text
app-a-test is 10.10.11.10

Which next hop should it use for 10.10.12.0/24?

A. 10.10.11.1
B. 10.10.11.2
C. 10.10.12.2
D. 10.10.12.10
```

Answer:

```text
B. 10.10.11.2
```

Because:

```text
10.10.11.2
=
lab-router on app-a-test's own subnet
```

Add the route:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ip route add 10.10.12.0/24 via 10.10.11.2
```

Confirm:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ip route get 10.10.12.10
```

Expected:

```text
10.10.12.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

The `/24` static route now wins over:

```text
default via 10.10.11.1
```

---

## Task 8: Test Again

Run:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ping -c 2 10.10.12.10
```

Prediction:

```text
The forward route is correct.

Will ping definitely work?
```

Not yet.

The request can now travel:

```text
app-a-test
      |
      v
lab-router
      |
      v
app-b-test
```

but the reply also needs a route back.

---

# Part 4: Build the Return Path

## Task 9: Inspect `app-b-test`

Run:

```bash
bash scripts/compose-stage.sh 05 exec app-b-test ip route
```

You should see:

```text
default via 10.10.12.1 dev eth0
10.10.12.0/24 dev eth0 scope link src 10.10.12.10
```

There is no specific route back to:

```text
10.10.11.0/24
```

Question:

```text
Which local router address should app-b-test use?

A. 10.10.11.2
B. 10.10.12.2
```

Correct:

```text
10.10.12.2
```

Add:

```bash
bash scripts/compose-stage.sh 05 exec app-b-test \
  ip route add 10.10.11.0/24 via 10.10.12.2
```

Now test again:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ping -c 2 10.10.12.10
```

Expected:

```text
2 packets transmitted, 2 packets received, 0% packet loss
```

The working path is:

```text
FORWARD

app-a-test
10.10.11.10
      |
      | 10.10.12.0/24 via 10.10.11.2
      v
lab-router
      |
      | 10.10.12.0/24 directly connected
      v
app-b-test
10.10.12.10
```

and:

```text
RETURN

app-b-test
10.10.12.10
      |
      | 10.10.11.0/24 via 10.10.12.2
      v
lab-router
      |
      | 10.10.11.0/24 directly connected
      v
app-a-test
10.10.11.10
```

---

# Part 5: Derive the General Rule

We have now proved one route manually.

Look at the pattern.

For `app-a-test`:

```text
local network = 10.10.11.0/24
local router  = 10.10.11.2
```

So every other lab subnet can use:

```text
via 10.10.11.2
```

For example:

```text
10.10.1.0/24  via 10.10.11.2
10.10.2.0/24  via 10.10.11.2
10.10.12.0/24 via 10.10.11.2
10.10.21.0/24 via 10.10.11.2
10.10.22.0/24 via 10.10.11.2
```

The same pattern applies to every endpoint.

## General Rule

```text
For each endpoint:

1. keep the connected route for its own subnet;
2. for every other lab subnet;
3. use lab-router's .2 address on the endpoint's local subnet.
```

So:

```text
public-a-test
local router = 10.10.1.2

public-b-test
local router = 10.10.2.2

app-a-test
local router = 10.10.11.2

app-b-test
local router = 10.10.12.2

db-a-test
local router = 10.10.21.2

db-b-test
local router = 10.10.22.2
```

---

# Part 6: Route Plan for All Six Endpoints

## `public-a-test`

```text
local IP     = 10.10.1.10
local router = 10.10.1.2
```

Remote routes:

```text
10.10.2.0/24  via 10.10.1.2
10.10.11.0/24 via 10.10.1.2
10.10.12.0/24 via 10.10.1.2
10.10.21.0/24 via 10.10.1.2
10.10.22.0/24 via 10.10.1.2
```

## `public-b-test`

```text
local IP     = 10.10.2.10
local router = 10.10.2.2
```

Remote routes:

```text
10.10.1.0/24  via 10.10.2.2
10.10.11.0/24 via 10.10.2.2
10.10.12.0/24 via 10.10.2.2
10.10.21.0/24 via 10.10.2.2
10.10.22.0/24 via 10.10.2.2
```

## `app-a-test`

```text
local IP     = 10.10.11.10
local router = 10.10.11.2
```

Remote routes:

```text
10.10.1.0/24  via 10.10.11.2
10.10.2.0/24  via 10.10.11.2
10.10.12.0/24 via 10.10.11.2
10.10.21.0/24 via 10.10.11.2
10.10.22.0/24 via 10.10.11.2
```

## `app-b-test`

```text
local IP     = 10.10.12.10
local router = 10.10.12.2
```

Remote routes:

```text
10.10.1.0/24  via 10.10.12.2
10.10.2.0/24  via 10.10.12.2
10.10.11.0/24 via 10.10.12.2
10.10.21.0/24 via 10.10.12.2
10.10.22.0/24 via 10.10.12.2
```

## `db-a-test`

```text
local IP     = 10.10.21.10
local router = 10.10.21.2
```

Remote routes:

```text
10.10.1.0/24  via 10.10.21.2
10.10.2.0/24  via 10.10.21.2
10.10.11.0/24 via 10.10.21.2
10.10.12.0/24 via 10.10.21.2
10.10.22.0/24 via 10.10.21.2
```

## `db-b-test`

```text
local IP     = 10.10.22.10
local router = 10.10.22.2
```

Remote routes:

```text
10.10.1.0/24  via 10.10.22.2
10.10.2.0/24  via 10.10.22.2
10.10.11.0/24 via 10.10.22.2
10.10.12.0/24 via 10.10.22.2
10.10.21.0/24 via 10.10.22.2
```

---

# Part 7: Why Chapter 06 Uses a Compose Overlay

We manually added routes to understand the rule.

Those manual routes are runtime state.

If the container is recreated:

```text
old container
     |
     v
old network namespace removed
     |
     v
manual route disappears
```

So Chapter 06 moves the known-good route commands into the service startup
configuration.

The Chapter 06 Compose file does not add new service names.

It contains entries such as:

```yaml
services:
  app-a-test:
    command:
      ...
```

The earlier chapters already define `app-a-test`.

When the runner starts Chapter 06, it loads all numbered Compose files through
Chapter 06:

```text
01
+
02
+
03
+
04
+
05
+
06
=
one final merged Compose configuration
```

Conceptually:

```text
earlier chapter
defines app-a-test

        +

Chapter 06
overrides app-a-test.command

        =

same logical Compose service
with new startup behavior
```

It is not:

```text
find an arbitrary already-running container
and execute commands inside it
```

Instead:

```text
Compose resolves the merged service configuration
        |
        v
service configuration changed
        |
        v
container may be recreated
        |
        v
new startup command runs
        |
        v
routes are installed
```

You can inspect the resolved configuration with:

```bash
bash scripts/compose-stage.sh 06 config
```

To inspect only service names:

```bash
bash scripts/compose-stage.sh 06 config --services
```

---

# Part 8: Why `ip route replace` Is Used

During the manual lesson we used:

```bash
ip route add ...
```

because we wanted to see the route being created.

Startup configuration uses:

```bash
ip route replace ...
```

because startup may happen repeatedly.

`replace` behaves like:

```text
route missing
    -> create it

route already exists
    -> update it
```

This makes it suitable for repeatable startup configuration.

Example:

```bash
ip route replace 10.10.12.0/24 via 10.10.11.2
```

Important:

```text
replace
!=
persistent by itself
```

The route still lives in the container's network namespace.

The reason it comes back after recreation is:

```text
container starts
      |
      v
startup command runs again
      |
      v
ip route replace ...
```

---

# Part 9: Apply Chapter 06

Before applying Chapter 06, remove the Chapter 05 baseline so the next start is
easy to reason about:

```bash
bash scripts/compose-stage.sh 05 down
```

Now start Chapter 06:

```bash
bash scripts/compose-stage.sh 06 up -d --build
```

Check the services:

```bash
bash scripts/compose-stage.sh 06 ps
```

The service set should still include:

```text
public-a-test
public-b-test
app-a-test
app-b-test
db-a-test
db-b-test
lab-router
```

No new service was introduced by Chapter 06.

---

# Part 10: Inspect the Automated Routes

## Task 10: Inspect `app-a-test`

Run:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test ip route
```

You should find routes to all five remote lab networks via:

```text
10.10.11.2
```

For example:

```text
10.10.1.0/24  via 10.10.11.2
10.10.2.0/24  via 10.10.11.2
10.10.12.0/24 via 10.10.11.2
10.10.21.0/24 via 10.10.11.2
10.10.22.0/24 via 10.10.11.2
```

Ask Linux which route it selects for `app-b-test`:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.12.10
```

Expected:

```text
10.10.12.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

Now compare a database destination:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.21.10
```

Expected next hop:

```text
10.10.11.2
```

The destination subnet changed.

The local router next hop did not.

---

# Part 11: Test Representative Paths

You do not need to ping every possible pair.

Test paths that prove the architecture.

## Public to Application

```bash
bash scripts/compose-stage.sh 06 exec public-a-test \
  ping -c 2 10.10.11.10
```

Expected path:

```text
public-a-test
10.10.1.10
      |
      | app_a via 10.10.1.2
      v
lab-router
      |
      | app_a directly connected
      v
app-a-test
10.10.11.10
```

---

## Application to Database

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.21.10
```

Expected path:

```text
app-a-test
10.10.11.10
      |
      | db_a via 10.10.11.2
      v
lab-router
      |
      | db_a directly connected
      v
db-a-test
10.10.21.10
```

---

## Cross-Side Application Path

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

---

## Public to Remote Database

```bash
bash scripts/compose-stage.sh 06 exec public-a-test \
  ping -c 2 10.10.22.10
```

This is a useful wider test because the source and destination belong to
different functional zones and opposite sides of the topology.

At this stage there is no restrictive firewall policy yet, so routed ICMP
traffic should work once both endpoint route tables are correct.

---

# Part 12: Inspect the Return Path

For the previous test:

```text
public-a-test
10.10.1.10

->

db-b-test
10.10.22.10
```

inspect the destination's route back to the source:

```bash
bash scripts/compose-stage.sh 06 exec db-b-test \
  ip route get 10.10.1.10
```

Expected next hop:

```text
10.10.22.2
```

So:

```text
FORWARD

public-a-test
10.10.1.10
      |
      | db_b via 10.10.1.2
      v
lab-router
      |
      v
db-b-test
10.10.22.10
```

and:

```text
RETURN

db-b-test
10.10.22.10
      |
      | public_a via 10.10.22.2
      v
lab-router
      |
      v
public-a-test
10.10.1.10
```

The source and destination use different router IP addresses because they are
on different local networks.

---

# Part 13: Confirm the Router Makes a Connected-Route Decision

Ask `lab-router` how it reaches `db-b-test`:

```bash
bash scripts/compose-stage.sh 06 exec lab-router \
  ip route get 10.10.22.10
```

The result should show that `10.10.22.10` is reached through the router
interface whose source address is:

```text
10.10.22.2
```

There should be no additional next-hop router.

That is the major difference from Chapter 05B.

Chapter 05B:

```text
router-1
   |
   | static route
   v
router-2
```

Chapter 06:

```text
lab-router
   |
   | connected route
   v
destination subnet
```

---

# Part 14: Recreate a Container

Routes added manually disappear when the network namespace disappears.

Chapter 06 should restore its routes when the service starts again.

Inspect first:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.21.10
```

Now recreate only `app-a-test`:

```bash
bash scripts/compose-stage.sh 06 up -d \
  --force-recreate app-a-test
```

Inspect again:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.21.10
```

Expected next hop before and after recreation:

```text
10.10.11.2
```

The original network namespace was destroyed.

The route exists again because the Chapter 06 startup command ran in the new
container.

---

# Part 15: Break It

Delete one specific route from `app-a-test`:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route delete 10.10.21.0/24 via 10.10.11.2
```

Now inspect:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.21.10
```

The selected route should no longer use:

```text
10.10.11.2
```

It may fall back to Docker's default route.

Now test:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.21.10
```

The intended lab path should fail.

---

# Part 16: Diagnose Before Fixing

Do not immediately recreate the container.

First ask:

```text
Where is the first incorrect routing decision?
```

Inspect the source:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.21.10
```

Inspect the router:

```bash
bash scripts/compose-stage.sh 06 exec lab-router \
  ip route get 10.10.21.10
```

The router should still know the destination because `db_a` is directly
connected.

So:

```text
source route broken
router route correct
```

The first broken layer is:

```text
app-a-test route table
```

This is the same debugging rule from Chapter 05B:

```text
follow the packet one routing decision at a time
```

---

# Part 17: Recover

Recreate `app-a-test`:

```bash
bash scripts/compose-stage.sh 06 up -d \
  --force-recreate app-a-test
```

Confirm:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.21.10
```

Expected:

```text
via 10.10.11.2
```

Retest:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.21.10
```

The route should work again.

---

# Key Mental Model

For every endpoint:

```text
destination on my subnet?
        |
     yes|no
        |
        +-------------------+
        |                   |
        v                   v
send directly      choose static route
                            |
                            v
                   local lab-router .2
```

For the router:

```text
packet arrives
      |
      v
route lookup
      |
      v
destination lab subnet
is directly connected
      |
      v
forward out matching interface
```

The complete model is:

```text
source endpoint
      |
      | static route
      v
local router .2
      |
      | connected route
      v
destination endpoint
```

For the reply:

```text
destination endpoint
      |
      | static return route
      v
its local router .2
      |
      | connected route
      v
original source
```

---

# Review Checkpoint

Answer these before moving to Chapter 07.

1. Why does `lab-router` not need static routes for the six original lab
   networks?
2. Why does `app-a-test` use `10.10.11.2` instead of `10.10.12.2` when
   reaching `app-b-test`?
3. What is the difference between Docker's `.1` gateway and the lab router's
   `.2` address?
4. What does `ip route get` prove?
5. What does it not prove?
6. Why can a correct forward route still result in a failed `ping`?
7. Why does every endpoint use a different `.2` next-hop address?
8. Why is `ip route replace` better than `ip route add` for startup
   configuration?
9. Does `ip route replace` itself make the route persistent?
10. What causes the route to return after container recreation?
11. Does Chapter 06 create six new endpoint services?
12. How does the Chapter 06 Compose file modify the existing services?

---

# Chapter Recap

Chapter 05 created the forwarding device:

```text
lab-router
+
six interfaces
+
six connected routes
+
ip_forward = 1
```

Chapter 05B taught the routing model:

```text
remote destination
      |
      v
choose a directly reachable next hop
      |
      v
repeat at every router
```

Chapter 06 applied that model to the real lab architecture.

Each endpoint learned:

```text
all remote lab subnets
        |
        v
lab-router's .2 address
on my own local subnet
```

The router did not need extra static routes because all six destination
networks were directly connected.

We first built one path manually:

```text
app-a-test
      |
      v
lab-router
      |
      v
app-b-test
```

Then we built the return path:

```text
app-b-test
      |
      v
lab-router
      |
      v
app-a-test
```

From that we derived the general rule for all six endpoints.

Finally, the Chapter 06 Compose overlay automated the already-understood
configuration with:

```bash
ip route replace ...
```

The important distinction is:

```text
manual routing
=
learn why the path works

startup routing
=
reapply the known-good path consistently
```

---

# Next Chapter

Routing answers:

```text
WHERE should the packet go?
```

So far, we have mostly inferred the packet path from:

```text
ip route
ip route get
ping
```

Chapter 07 adds packet capture with `tcpdump`.

The next question becomes:

```text
Can we actually observe the packet
entering and leaving lab-router?
```

The progression is:

```text
Chapter 06
route selection + end-to-end reachability
        |
        v
Chapter 07
packet-level evidence
at router ingress and egress
```

---

# Clean Up

When finished:

```bash
bash scripts/compose-stage.sh 06 down
```
