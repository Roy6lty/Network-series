# Chapter 03: Network Namespaces and Interfaces

![Chapter 03 network namespace](diagram.svg)

## Key Concepts

### What Is a Network Namespace?

A **network namespace** gives a process its own isolated view of the Linux
networking stack.

A network namespace can have its own:

- network interfaces;
- loopback interface;
- IP addresses;
- routing table;
- neighbor table;
- firewall rules;
- sockets.

Docker creates a network namespace for each container.

This is why running:

```bash
ip addr
```

inside two different containers can show different interfaces and IP addresses
even though both containers are running on the same Linux host.

Conceptually:

```text
Linux Host
|
+-- Container A network namespace
|   |
|   +-- lo
|   +-- eth0
|   +-- routes
|   +-- neighbor table
|
+-- Container B network namespace
    |
    +-- lo
    +-- eth0
    +-- routes
    +-- neighbor table
```

Each container sees its own networking environment.

---

### Virtual Ethernet Interfaces

A container's network interface is usually one end of a **virtual Ethernet
pair**, commonly called a `veth` pair.

A veth pair behaves like a virtual network cable:

```text
Container namespace                    Host namespace

eth0
 |
 | virtual Ethernet pair
 |
 v
vethXXXXXXXX
 |
 v
Docker bridge
```

One end is moved into the container's network namespace and usually appears as:

```text
eth0
```

The other end remains on the host and is connected to the Docker bridge.

This is how packets move between the container and the Docker bridge.

---

### Loopback Interface

Every container network namespace also has a loopback interface:

```text
lo
```

with the IPv4 address:

```text
127.0.0.1
```

The loopback interface allows processes inside the same network namespace to
communicate with themselves.

For example:

```text
127.0.0.1:8000
```

refers to a service running inside that same container.

It does not refer to the Docker host or another container.

---

### Routing Table

Every network namespace has its own routing table.

The routing table tells the Linux kernel:

> Where should this packet go, and which interface or next hop should be used?

For example:

```text
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
```

means the `10.10.11.0/24` network is directly reachable through `eth0`.

---

### Neighbor Table

Linux keeps a **neighbor table** containing learned information about local
Layer-2 neighbors.

For IPv4, these entries are normally learned using ARP.

The command is:

```bash
ip neigh
```

An entry may look like:

```text
10.10.11.1 dev eth0 lladdr 02:42:xx:xx:xx:xx REACHABLE
```

This means Linux has learned:

```text
10.10.11.1
```

maps to the MAC address:

```text
02:42:xx:xx:xx:xx
```

on `eth0`.

The neighbor table is **not a list of every machine on the network**.

It is a cache of local neighbors that the kernel has learned about while
resolving next-hop addresses or exchanging local network traffic.

---

## Goal

Inspect the network namespace Docker created for a container and identify:

- the loopback interface;
- the container's network interface;
- its IP address;
- its connected route;
- its neighbor table;
- how the neighbor table changes after network traffic is generated.

This chapter changes no network topology.

We are inspecting the networking environment created in Chapter 02 before
introducing Linux capabilities and routing.

---

## What This Stage Adds

No new network devices or routes are added.

The topology remains:

```text
+-------------------------+      +-------------------------+
| public_a 10.10.1.0/24   |      | public_b 10.10.2.0/24   |
|                         |      |                         |
| public-a-test           |      | public-b-test           |
| 10.10.1.10              |      | 10.10.2.10              |
+-------------------------+      +-------------------------+


+-------------------------+      +-------------------------+
| app_a 10.10.11.0/24     |      | app_b 10.10.12.0/24     |
|                         |      |                         |
| app-a-test              |      | app-b-test              |
| 10.10.11.10             |      | 10.10.12.10             |
+-------------------------+      +-------------------------+


+-------------------------+      +-------------------------+
| db_a 10.10.21.0/24      |      | db_b 10.10.22.0/24      |
|                         |      |                         |
| db-a-test               |      | db-b-test               |
| 10.10.21.10             |      | 10.10.22.10             |
+-------------------------+      +-------------------------+
```

Each test container is still on a separate Docker bridge network.

There is still no router connecting the six networks.

---

## Tasks

1. Start the Chapter 03 lab.
2. Inspect the interfaces inside `app-a-test`.
3. Inspect its routing table.
4. Inspect its neighbor table.
5. Generate traffic to a local neighbor.
6. Inspect the neighbor table again.
7. Ask Linux how it would route traffic toward another subnet.

---

## Checkpoint

### 1. Start the Lab

```bash
bash scripts/compose-stage.sh 03 up -d
```

Confirm the containers are running:

```bash
bash scripts/compose-stage.sh 03 ps
```

---

## Inspect the Network Interfaces

Run:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip addr
```

You should see something similar to:

```text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 ...
    inet 127.0.0.1/8 scope host lo

2: eth0@if...: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
    inet 10.10.11.10/24 brd 10.10.11.255 scope global eth0
```

The important interfaces are:

```text
lo
= loopback interface

eth0
= container network interface
```

The address:

```text
10.10.11.10/24
```

belongs to `app-a-test`.

> Note: the Alpine image initially uses BusyBox's lightweight `ip` command.
> Some BusyBox versions do not support `ip -br addr`, so this course uses
> `ip addr` unless the full `iproute2` package has been installed.

---

## Inspect the Routing Table

Run:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip route
```

Expected output should include:

```text
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
```

Breakdown:

```text
10.10.11.0/24
= destination network

dev eth0
= packets for this network use eth0

scope link
= this network is directly connected

src 10.10.11.10
= use this IP as the source address
```

The kernel does not need a router to reach another address inside:

```text
10.10.11.0/24
```

because that network is directly connected.

---

## Inspect the Neighbor Table

Run:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
```

The table may initially be empty or contain previously learned entries.

That is normal.

Linux does not automatically maintain a complete inventory of every device on
the network.

---

## Generate Local Network Traffic

The Docker bridge gateway for `app_a` is:

```text
10.10.11.1
```

Ping it:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ping -c 2 10.10.11.1
```

The destination is inside the same `/24` network:

```text
app-a-test
10.10.11.10
    |
    | same subnet
    v
10.10.11.1
Docker bridge gateway
```

Before sending the Ethernet frame, Linux needs the destination's MAC address.

It therefore performs ARP roughly like:

```text
Who has 10.10.11.1?
Tell 10.10.11.10.
```

The gateway replies with its MAC address.

---

## Inspect the Neighbor Table Again

Run:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
```

You should now see an entry similar to:

```text
10.10.11.1 dev eth0 lladdr 02:42:xx:xx:xx:xx REACHABLE
```

This demonstrates the relationship:

```text
routing table
     |
     | destination is local
     v
ARP
     |
     | resolve IP to MAC
     v
neighbor table
     |
     v
Ethernet frame sent
```

---

## Inspect a Route to Another Subnet

Now ask the kernel how it would reach `app-b-test`:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test \
  ip route get 10.10.12.10
```

`app-b-test` has the address:

```text
10.10.12.10
```

and lives on:

```text
app_b
10.10.12.0/24
```

while the command is being run from:

```text
app-a-test
10.10.11.10
```

which lives on:

```text
app_a
10.10.11.0/24
```

These are different subnets.

At this stage, there is no lab router and no specific route connecting:

```text
10.10.11.0/24
```

to:

```text
10.10.12.0/24
```

The important observation is that there is no valid lab routing path between
the two networks yet.

---

## Expected Observation

The container has its own networking state:

```text
app-a-test network namespace
|
+-- lo
|   +-- 127.0.0.1
|
+-- eth0
|   +-- 10.10.11.10/24
|
+-- routing table
|   +-- 10.10.11.0/24 is directly connected
|
+-- neighbor table
    +-- learned local IP-to-MAC mappings
```

A local destination such as:

```text
10.10.11.1
```

can be reached directly through `eth0`.

A remote destination such as:

```text
10.10.12.10
```

belongs to another subnet and will eventually require a router.

---

## Break It

Try to reach `app-b-test` from `app-a-test`:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test \
  ping -c 2 10.10.12.10
```

The important addresses are:

```text
app-a-test
10.10.11.10
network: app_a

app-b-test
10.10.12.10
network: app_b
```

The failure is expected because the containers are on different Docker bridge
networks and no router currently exists between them.

Then inspect the routing table again:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip route
```

and inspect the neighbor table:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
```

Notice that learning MAC addresses in the neighbor table does not solve
communication between different subnets.

ARP operates on the local Layer-2 network.

Routing is required to move traffic between Layer-3 networks.

This distinction becomes important when the lab router is introduced.

---

## Key Mental Model

```text
Interface
= where the container sends and receives packets

Routing table
= which interface or next hop should be used for a destination

Neighbor table
= learned MAC address for a local next hop
```

In packet-flow order:

```text
Destination IP
      |
      v
Routing table
      |
      v
Select interface / next hop
      |
      v
Neighbor table / ARP
      |
      v
Resolve next-hop MAC address
      |
      v
Send Ethernet frame
```

---

## Clean Up

Remove the resources created for this stage:

```bash
bash scripts/compose-stage.sh 03 down
```
