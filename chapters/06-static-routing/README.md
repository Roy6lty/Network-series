# Chapter 06: Static Routing

![Chapter 06 forward and return routes](diagram.svg)

## Key Concepts

### What Is a Static Route?

A static route is a route that is explicitly configured instead of being
learned from a routing protocol.

It tells Linux:

```text
for this destination network,
send the packet to this next hop
```

For example, `app-a-test` uses:

```text
10.10.12.0/24 via 10.10.11.2
```

This means:

```text
traffic for 10.10.12.0/24
        -> send to 10.10.11.2
        -> use the local app_a interface
```

The address `10.10.11.2` belongs to `lab-router` on the same subnet as
`app-a-test`.

---

### What Is a Next Hop?

A next hop is the directly reachable device that receives a packet next.

The next hop must be reachable on the sender's local network.

For `app-a-test`:

```text
app-a-test
10.10.11.10
        |
        | same app_a subnet
        v
lab-router
10.10.11.2
```

This is a valid next hop.

The address `10.10.12.2` is the router's address on a different subnet. It is
not a valid next hop directly from `app-a-test` because `app-a-test` cannot
reach that interface at Layer 2.

So:

```text
valid:
10.10.12.0/24 via 10.10.11.2

invalid from app-a-test:
10.10.12.0/24 via 10.10.12.2
```

The next hop is always selected from the sender's local network.

---

### Forward and Return Paths

A packet needs a route from the source to the destination:

```text
forward path:
app-a-test -> lab-router -> app-b-test
```

The response needs a route in the opposite direction:

```text
return path:
app-b-test -> lab-router -> app-a-test
```

Both paths are required for a complete connection.

For example, the request from `app-a-test` to `app-b-test` uses:

```text
10.10.12.0/24 via 10.10.11.2
```

The reply from `app-b-test` uses:

```text
10.10.11.0/24 via 10.10.12.2
```

The two routes use different router interfaces because each endpoint sends to
the router address on its own local subnet.

---

### Most-Specific Route Wins

Linux compares a destination with the routes in its routing table.

It chooses the most-specific matching route before considering a broader route
or the default route.

For `app-a-test`, the table may contain:

```text
10.10.12.0/24 via 10.10.11.2
default via 10.10.11.1
```

When the destination is `10.10.12.10`, the `/24` route wins over the default
route:

```text
10.10.12.10
        |
        v
10.10.12.0/24 via 10.10.11.2
```

The Docker gateway `10.10.11.1` is used only when no more-specific route
matches.

---

### Runtime Route State

Routes added with `ip route add` or `ip route replace` live in the container's
network namespace.

They are runtime state:

```text
container recreated
        |
        v
network namespace recreated
        |
        v
runtime route disappears
```

Chapter 06 puts the route commands in the Compose service command so the routes
are reapplied when each container starts.

This is not the same as storing a route in the host operating system.

---

## Goal

Teach the six diagnostic containers how to reach remote lab subnets through the
multi-homed `lab-router`.

By the end of this chapter you should be able to:

- identify a missing remote route;
- choose a valid local next hop;
- explain why a default Docker gateway is not the lab router;
- inspect route selection with `ip route get`;
- distinguish a forward route from a return route;
- test routed connectivity across the lab subnets;
- understand why `ip route replace` is used at container startup;
- diagnose a failure caused by a missing route.

---

## Chapter Progression

Chapter 05 introduced a router connected to all six networks.

At the end of Chapter 05, the router knows every connected subnet, but the
client containers still know only about their own local networks.

```text
Chapter 05
router exists
        +
clients have local routes only
        |
        v
Chapter 06
clients receive remote static routes
        +
forward path
        +
return path
        +
end-to-end connectivity
```

The optional Chapter 05B lesson explores the same routing idea with a chain of
three routers. This Chapter 06 lesson returns to the standard six-network lab
with one router attached to every subnet.

---

## What This Stage Adds

This chapter adds no new containers or networks.

The existing six diagnostic containers receive startup commands that install
routes to every remote subnet.

The router remains:

```text
lab-router
10.10.1.2    on public_a
10.10.2.2    on public_b
10.10.11.2   on app_a
10.10.12.2   on app_b
10.10.21.2   on db_a
10.10.22.2   on db_b
```

The six endpoint containers remain:

```text
public-a-test   10.10.1.10
public-b-test   10.10.2.10
app-a-test      10.10.11.10
app-b-test      10.10.12.10
db-a-test       10.10.21.10
db-b-test       10.10.22.10
```

The topology is:

```text
                         lab-router
                  one interface per subnet
                              |
       +----------------------+----------------------+
       |                      |                      |
   public_a                app_a                  db_a
 10.10.1.0/24          10.10.11.0/24          10.10.21.0/24
       |                      |                      |
public-a-test           app-a-test               db-a-test
 10.10.1.10             10.10.11.10              10.10.21.10

       |                      |                      |
       +----------------------+----------------------+
                              |
                         lab-router
                  one interface per subnet
                              |
       +----------------------+----------------------+
       |                      |                      |
   public_b                app_b                  db_b
 10.10.2.0/24           10.10.12.0/24          10.10.22.0/24
       |                      |                      |
public-b-test           app-b-test               db-b-test
 10.10.2.10             10.10.12.10              10.10.22.10
```

The router is one container with six interfaces. A client must still be taught
which local router interface to use for each remote destination.

---

## Important Lab Rule

Chapter 05B asks the learner to add routes manually. Chapter 06 intentionally
automates the known-good routes in the Compose overlay after the routing model
has been introduced.

The route commands use:

```bash
ip route replace DESTINATION via NEXT_HOP
```

`replace` is used instead of `add` because it is safe to run when the route is
already present:

```text
route missing
        -> create it

route already exists
        -> update it without creating a duplicate
```

The command runs before `sleep infinity`, so the container stays alive after
the route setup completes.

---

## Route Plan

Each endpoint uses the router address on its own subnet as the next hop.

### `public-a-test`

Local address:

```text
10.10.1.10
```

Router next hop:

```text
10.10.1.2
```

Remote routes:

```text
10.10.2.0/24 via 10.10.1.2
10.10.11.0/24 via 10.10.1.2
10.10.12.0/24 via 10.10.1.2
10.10.21.0/24 via 10.10.1.2
10.10.22.0/24 via 10.10.1.2
```

### `public-b-test`

Local address:

```text
10.10.2.10
```

Router next hop:

```text
10.10.2.2
```

Remote routes:

```text
10.10.1.0/24 via 10.10.2.2
10.10.11.0/24 via 10.10.2.2
10.10.12.0/24 via 10.10.2.2
10.10.21.0/24 via 10.10.2.2
10.10.22.0/24 via 10.10.2.2
```

### `app-a-test`

Local address:

```text
10.10.11.10
```

Router next hop:

```text
10.10.11.2
```

Remote routes:

```text
10.10.1.0/24 via 10.10.11.2
10.10.2.0/24 via 10.10.11.2
10.10.12.0/24 via 10.10.11.2
10.10.21.0/24 via 10.10.11.2
10.10.22.0/24 via 10.10.11.2
```

### `app-b-test`

Local address:

```text
10.10.12.10
```

Router next hop:

```text
10.10.12.2
```

Remote routes:

```text
10.10.1.0/24 via 10.10.12.2
10.10.2.0/24 via 10.10.12.2
10.10.11.0/24 via 10.10.12.2
10.10.21.0/24 via 10.10.12.2
10.10.22.0/24 via 10.10.12.2
```

### `db-a-test`

Local address:

```text
10.10.21.10
```

Router next hop:

```text
10.10.21.2
```

Remote routes:

```text
10.10.1.0/24 via 10.10.21.2
10.10.2.0/24 via 10.10.21.2
10.10.11.0/24 via 10.10.21.2
10.10.12.0/24 via 10.10.21.2
10.10.22.0/24 via 10.10.21.2
```

### `db-b-test`

Local address:

```text
10.10.22.10
```

Router next hop:

```text
10.10.22.2
```

Remote routes:

```text
10.10.1.0/24 via 10.10.22.2
10.10.2.0/24 via 10.10.22.2
10.10.11.0/24 via 10.10.22.2
10.10.12.0/24 via 10.10.22.2
10.10.21.0/24 via 10.10.22.2
```

---

## Tasks

1. Start the Chapter 05 baseline and observe the missing client route.
2. Apply the Chapter 06 overlay.
3. Inspect the routes installed in `app-a-test`.
4. Ask Linux which next hop it selects for `app-b-test`.
5. Confirm the router is forwarding IPv4 packets.
6. Test connectivity between application networks.
7. Test connectivity between public and database networks.
8. Inspect the return route on the destination container.
9. Recreate a service and confirm its routes are reapplied.
10. Delete a forward or return route and observe the failure.

---

## Checkpoint

# Part 1: Observe the Chapter 05 Baseline

## Task 1: Start the Previous Stage

Start the standard Chapter 05 topology:

```bash
bash scripts/compose-stage.sh 05 up -d --build
```

Confirm that the containers are running:

```bash
bash scripts/compose-stage.sh 05 ps
```

The important services are:

```text
public-a-test
public-b-test
app-a-test
app-b-test
db-a-test
db-b-test
lab-router
```

Chapter 05 provides the router and enables IPv4 forwarding, but it does not yet
teach the clients about remote subnets.

---

## Task 2: Inspect `app-a-test` Before Static Routes

Inspect its route table:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test ip route
```

You should see its directly connected network and Docker's default route:

```text
default via 10.10.11.1 dev eth0
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
```

The exact output may also include `proto kernel` and other fields.

At this point, `app-a-test` knows:

```text
10.10.11.0/24 is local
10.10.11.1 is the Docker default gateway
```

It does not yet have a specific route for:

```text
10.10.12.0/24
```

---

## Task 3: Ask Linux for the Current Route

Ask Linux how it would reach `app-b-test`:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ip route get 10.10.12.10
```

The result should use Docker's default gateway:

```text
10.10.12.10 via 10.10.11.1 dev eth0 src 10.10.11.10
```

The exact output may include `uid 0` or other kernel metadata.

Breakdown:

```text
destination = 10.10.12.10
next hop    = 10.10.11.1
interface   = eth0
source IP   = 10.10.11.10
```

The route lookup does not prove that the destination is reachable. It only
shows the decision Linux would make with the current table.

---

## Task 4: Test the Baseline

Try to reach `app-b-test`:

```bash
bash scripts/compose-stage.sh 05 exec app-a-test \
  ping -c 2 10.10.12.10
```

The failure is expected because the client has not been given a route through
the lab router.

The important distinction is:

```text
lab-router exists
        !=
app-a-test knows to use lab-router
```

---

# Part 2: Apply the Static-Routing Overlay

## Task 5: Start Chapter 06

Apply the Chapter 06 Compose overlay:

```bash
bash scripts/compose-stage.sh 06 up -d --build
```

The Chapter 06 overlay changes the command for each diagnostic service. Each
service now runs its route setup before `sleep infinity`.

Confirm the services again:

```bash
bash scripts/compose-stage.sh 06 ps
```

The topology still contains six endpoint networks, one endpoint per network,
and the single multi-homed `lab-router`.

---

## Task 6: Inspect the New `app-a-test` Route Table

Run:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test ip route
```

You should now find entries similar to:

```text
default via 10.10.11.1 dev eth0
10.10.1.0/24 via 10.10.11.2 dev eth0
10.10.2.0/24 via 10.10.11.2 dev eth0
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
10.10.12.0/24 via 10.10.11.2 dev eth0
10.10.21.0/24 via 10.10.11.2 dev eth0
10.10.22.0/24 via 10.10.11.2 dev eth0
```

The order may vary. The important change is the presence of specific routes to
the five remote networks.

For example:

```text
10.10.12.0/24 via 10.10.11.2
```

The endpoint now knows that remote application traffic must first go to the
router's `app_a` interface.

---

## Task 7: Inspect the Overlay's Command

Ask Compose to show the resolved Chapter 06 configuration:

```bash
bash scripts/compose-stage.sh 06 config
```

Find the `app-a-test` command. It contains commands similar to:

```yaml
command:
  - sh
  - -c
  - |
    set -eu
    ip route replace 10.10.1.0/24 via 10.10.11.2
    ip route replace 10.10.2.0/24 via 10.10.11.2
    ip route replace 10.10.12.0/24 via 10.10.11.2
    ip route replace 10.10.21.0/24 via 10.10.11.2
    ip route replace 10.10.22.0/24 via 10.10.11.2
    sleep infinity
```

The Compose overlay does not change the network addresses. It changes the
startup behavior inside the endpoint container.

---

# Part 3: Inspect Route Selection

## Task 8: Use `ip route get` for a Remote Destination

Ask Linux how `app-a-test` reaches `app-b-test`:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.12.10
```

Expected output:

```text
10.10.12.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

The next hop changed from the Docker gateway:

```text
10.10.11.1
```

to the lab router:

```text
10.10.11.2
```

This is the main change introduced by Chapter 06.

---

## Task 9: Compare Local and Remote Destinations

Ask Linux how it reaches the local router:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.11.2
```

The router address is directly connected, so no remote next hop is needed.

Now ask how it reaches the remote database endpoint:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.22.10
```

Expected output:

```text
10.10.22.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

The endpoint does not send directly to `10.10.22.10`. It sends first to the
router on `app_a`.

---

## Task 10: Compare a Remote Route With the Default Route

Ask Linux how it reaches an unrelated address:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 8.8.8.8
```

If a default route is present, the result should use:

```text
10.10.11.1
```

The specific lab route still wins for `10.10.22.10` because:

```text
10.10.22.0/24
```

is more specific than:

```text
default
```

This is why the Docker default gateway does not override the static route.

---

# Part 4: Confirm Router Forwarding

## Task 11: Inspect `lab-router`

The client route only identifies the first next hop. The router must also have
the destination network in its own table.

Inspect the router:

```bash
bash scripts/compose-stage.sh 06 exec lab-router ip route
```

The router should have connected routes for all six networks:

```text
10.10.1.0/24 dev ethX scope link src 10.10.1.2
10.10.2.0/24 dev ethX scope link src 10.10.2.2
10.10.11.0/24 dev ethX scope link src 10.10.11.2
10.10.12.0/24 dev ethX scope link src 10.10.12.2
10.10.21.0/24 dev ethX scope link src 10.10.21.2
10.10.22.0/24 dev ethX scope link src 10.10.22.2
```

The interface names and extra route fields may vary.

These are connected routes because the router has an interface in every subnet.

The router does not need a static route for these six networks.

---

## Task 12: Confirm IPv4 Forwarding

Run:

```bash
bash scripts/compose-stage.sh 06 exec lab-router \
  sysctl net.ipv4.ip_forward
```

Expected output:

```text
net.ipv4.ip_forward = 1
```

The router needs both:

```text
routes
       +
IPv4 forwarding enabled
```

Without forwarding, the router could communicate with endpoints itself but
would not move packets between endpoint networks.

---

## Task 13: Inspect the Router's Route Decision

Ask the router how it reaches `db-b-test`:

```bash
bash scripts/compose-stage.sh 06 exec lab-router \
  ip route get 10.10.22.10
```

The result should select the router's directly connected `db_b` interface and
source address `10.10.22.2`:

```text
10.10.22.10 dev ethX src 10.10.22.2
```

The complete forward decision is now visible:

```text
app-a-test route:
10.10.22.0/24 via 10.10.11.2

lab-router route:
10.10.22.0/24 is directly connected
```

---

# Part 5: Test the Forward Path

## Task 14: Reach the Router Interface

First test the local router interface:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.11.2
```

Expected result:

```text
2 packets transmitted, 2 packets received, 0% packet loss
```

This confirms that `app-a-test` can reach its next hop on the local `app_a`
network.

It does not yet prove that the router can forward traffic to a remote endpoint.

---

## Task 15: Reach `app-b-test`

Now test the routed path:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

Expected result:

```text
2 packets transmitted, 2 packets received, 0% packet loss
```

The request path is:

```text
app-a-test
10.10.11.10
        |
        | next hop 10.10.11.2
        v
lab-router
10.10.11.2 -> 10.10.12.2
        |
        | connected app_b network
        v
app-b-test
10.10.12.10
```

The source and destination addresses remain the endpoint addresses. The router
forwards the packet; it does not perform NAT in this chapter.

---

## Task 16: Reach a Database Network

Test a path that crosses from the application zone to the database zone:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.22.10
```

The path is:

```text
app-a-test 10.10.11.10
        |
        | via 10.10.11.2
        v
lab-router
        |
        | connected db_b route
        v
db-b-test 10.10.22.10
```

The route on `app-a-test` is:

```text
10.10.22.0/24 via 10.10.11.2
```

The route on the router is automatic because `db_b` is directly attached.

---

## Task 17: Test the Public-to-Database Path

Test another source and destination pair:

```bash
bash scripts/compose-stage.sh 06 exec public-a-test \
  ping -c 2 10.10.22.10
```

The source uses the router address on `public_a`:

```text
10.10.22.0/24 via 10.10.1.2
```

The router forwards the packet out its `db_b` interface:

```text
10.10.22.2
```

This test demonstrates that the static routes are installed in every endpoint,
not only in the application containers.

---

# Part 6: Confirm the Return Path

## Task 18: Inspect `app-b-test`

The destination must know how to return traffic to `app-a-test`.

Inspect its route table:

```bash
bash scripts/compose-stage.sh 06 exec app-b-test ip route
```

Find the route:

```text
10.10.11.0/24 via 10.10.12.2
```

This route sends the reply to the router's `app_b` interface.

---

## Task 19: Ask for the Return Route

```bash
bash scripts/compose-stage.sh 06 exec app-b-test \
  ip route get 10.10.11.10
```

Expected output:

```text
10.10.11.10 via 10.10.12.2 dev eth0 src 10.10.12.10
```

The complete exchange is:

```text
request:
app-a-test -> 10.10.11.2 -> app-b-test

reply:
app-b-test -> 10.10.12.2 -> app-a-test
```

The next-hop addresses differ because each endpoint is attached to a different
subnet.

---

## Task 20: Trace the Path

If `traceroute` is available in the lab image, run:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  traceroute -n -m 3 -w 1 10.10.12.10
```

Expected sequence:

```text
1  10.10.11.2
2  10.10.12.10
```

The exact formatting may vary.

The important observation is that the router appears as an intermediate hop.

For this one-router topology:

```text
app-a-test -> lab-router -> app-b-test
```

The `ping` command proves reachability. `traceroute` makes the Layer-3 path
visible.

---

# Part 7: Understand Route Persistence

## Task 21: Recreate `app-a-test`

Routes are stored in the container network namespace, so recreating a service
removes its current runtime route table.

Recreate the service with the Chapter 06 overlay:

```bash
bash scripts/compose-stage.sh 06 up -d --force-recreate app-a-test
```

Inspect the route again:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.22.10
```

The route should still use:

```text
10.10.11.2
```

Why did it return?

Because the service command ran again:

```text
container created
        |
        v
route setup command executed
        |
        v
sleep infinity
```

This is a simple form of runtime configuration persistence.

---

## Task 22: Understand `replace`

Run the same route replacement manually:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route replace 10.10.22.0/24 via 10.10.11.2
```

Inspect the matching route:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.22.10
```

It should still identify the same next hop.

`replace` does not create duplicate equivalent routes. It ensures that the
desired route is present with the desired next hop.

---

# Part 8: Break the Forward Path

## Task 23: Delete the Forward Route

Delete the route from `app-a-test` to `app-b-test`:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route delete 10.10.12.0/24 via 10.10.11.2
```

Confirm the specific route is gone:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.12.10
```

Linux should now select the default Docker gateway instead of the lab router:

```text
10.10.12.10 via 10.10.11.1 dev eth0 src 10.10.11.10
```

Test again:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

The routed path should fail.

The router is still running and forwarding. The failure occurs before the
packet reaches the intended lab-router interface because the source selected
the wrong next hop.

---

## Task 24: Restore the Forward Route

Recreate `app-a-test` so the startup command reapplies the route:

```bash
bash scripts/compose-stage.sh 06 up -d --force-recreate app-a-test
```

Confirm:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.12.10
```

Expected:

```text
10.10.12.10 via 10.10.11.2 dev eth0 src 10.10.11.10
```

Retest:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

---

# Part 9: Break the Return Path

## Task 25: Delete the Destination's Return Route

Delete the route from `app-b-test` back to `app-a-test`:

```bash
bash scripts/compose-stage.sh 06 exec app-b-test \
  ip route delete 10.10.11.0/24 via 10.10.12.2
```

Confirm the route decision changed:

```bash
bash scripts/compose-stage.sh 06 exec app-b-test \
  ip route get 10.10.11.10
```

It should now use the Docker default gateway:

```text
10.10.11.10 via 10.10.12.1 dev eth0 src 10.10.12.10
```

Test from the source again:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

The request may reach `app-b-test`, but the reply cannot use the correct route
back through the lab router.

This is the key observation:

```text
forward route present
        !=
complete connection
```

---

## Task 26: Restore the Return Route

Recreate `app-b-test`:

```bash
bash scripts/compose-stage.sh 06 up -d --force-recreate app-b-test
```

Confirm the return route:

```bash
bash scripts/compose-stage.sh 06 exec app-b-test \
  ip route get 10.10.11.10
```

Expected:

```text
10.10.11.10 via 10.10.12.2 dev eth0 src 10.10.12.10
```

Retest the connection:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

The route setup command restores the complete path.

---

## Important Observation

A successful ping requires all of these decisions to be correct:

```text
source route
        +
reachable local next hop
        +
router connected destination route
        +
router IPv4 forwarding
        +
destination return route
        =
successful exchange
```

The first failure in this chain determines where troubleshooting should begin.

Use `ip route get` at each node instead of guessing:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.12.10

bash scripts/compose-stage.sh 06 exec lab-router \
  ip route get 10.10.12.10

bash scripts/compose-stage.sh 06 exec app-b-test \
  ip route get 10.10.11.10
```

These three commands show:

```text
source next hop
router destination decision
destination return next hop
```

---

## Expected Observation

Before Chapter 06, `app-a-test` selected:

```text
10.10.12.10 via 10.10.11.1
```

After Chapter 06, it selects:

```text
10.10.12.10 via 10.10.11.2
```

The packet path is:

```text
app-a-test
10.10.11.10
        |
        | 10.10.12.0/24 via 10.10.11.2
        v
lab-router
10.10.11.2
        |
        | connected route to 10.10.12.0/24
        v
app-b-test
10.10.12.10
```

The return path is:

```text
app-b-test
10.10.12.10
        |
        | 10.10.11.0/24 via 10.10.12.2
        v
lab-router
10.10.12.2
        |
        | connected route to 10.10.11.0/24
        v
app-a-test
10.10.11.10
```

The router is the forwarding device, but each endpoint still needs a route
pointing to the correct router interface.

---

## Key Mental Model

```text
connected route
= Linux knows the network because an interface is attached to it
```

```text
static route
= an explicit destination and next-hop relationship
```

```text
next hop
= the directly reachable device that receives the packet next
```

```text
default route
= fallback route used when no more-specific route matches
```

```text
forward path
= source to destination route decisions
```

```text
return path
= destination to source route decisions
```

For `app-a-test` reaching `app-b-test`:

```text
destination 10.10.12.10
        |
        v
match 10.10.12.0/24
        |
        v
next hop 10.10.11.2
        |
        v
lab-router forwards
        |
        v
app-b-test replies via 10.10.12.2
```

And most importantly:

```text
router exists
        !=
client has a route to the router
```

```text
forward route
        +
return route
        =
working exchange
```

---

## Review Checkpoint

Answer these questions without looking at the final route table:

1. Why is `10.10.11.2` a valid next hop for `app-a-test`?
2. Why is `10.10.12.2` not the first next hop from `app-a-test`?
3. Why does the specific `/24` route win over the Docker default route?
4. What route does `app-b-test` need to reply to `app-a-test`?
5. Why can the router use connected routes without static routes for the six lab networks?
6. What does `ip route get` show?
7. Why can a packet reach the destination while the connection still fails?
8. What happens to runtime routes when a container is recreated?
9. Why does the Compose command use `ip route replace` instead of only `ip route add`?
10. Which node should you inspect first when a remote ping fails?

---

## Clean Up

Remove the resources created for the standard cumulative lab:

```bash
bash scripts/compose-stage.sh 06 down
```
