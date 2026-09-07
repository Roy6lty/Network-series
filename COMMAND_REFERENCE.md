# Docker Networking Lab Command Reference

This is the command guide for the Docker Networking VPC Lab.

Use the first part as a quick reference while working through a chapter. Use
the later sections when you need to understand what a command changes, how to
read its output, or which layer to investigate when a test fails.

The commands in this guide are intended for the disposable lab environment.
Several of them change live network, firewall, or process state.

## Before You Start

Run commands from the repository root unless a section says otherwise:

```bash
cd /path/to/docker-subnet
```

The course runner selects the Compose files for a stage and then invokes Docker
Compose:

```bash
bash scripts/compose-stage.sh STAGE DOCKER_COMPOSE_COMMAND [ARGS...]
```

Examples:

```bash
bash scripts/compose-stage.sh 06 up -d
bash scripts/compose-stage.sh 06 ps
bash scripts/compose-stage.sh 06 exec app-a-test ip route
```

Run commands in the correct place:

```text
host command
= run in your normal terminal

runner command
= run through scripts/compose-stage.sh

container command
= run after compose exec selects a container
```

The same command can produce different results on the host and in a container
because they have different network namespaces, interfaces, routes, and
firewall state.

## Quick Reference

| Command | Main question answered | Common lab example |
|---|---|---|
| `bash scripts/compose-stage.sh` | Which Compose stage and service should run? | `... 06 exec app-a-test ip route` |
| `docker compose config` | What configuration will Compose apply? | `... 06 config` |
| `docker ps` | Which containers exist and are running? | `docker ps` |
| `docker network ls` | Which Docker networks exist? | `docker network ls` |
| `docker network inspect` | Which containers and addresses are on a network? | `docker network inspect docker-subnet_app_a` |
| `ip addr` | Which interfaces and addresses does this namespace have? | `... exec app-a-test ip addr` |
| `ip route` | Which destinations and next hops are configured? | `... exec app-a-test ip route` |
| `ip route get` | Which route will Linux choose for one destination? | `... exec app-a-test ip route get 10.10.22.10` |
| `ip neigh` | Which local IP-to-MAC mappings are cached? | `... exec app-a-test ip neigh` |
| `ping` | Can an endpoint exchange ICMP echo packets? | `... exec app-a-test ping -c 2 10.10.12.10` |
| `traceroute` | Which Layer-3 hops appear on the path? | `... exec app-a-test traceroute -n 10.10.12.10` |
| `sysctl` | Is a kernel setting such as forwarding enabled? | `... exec lab-router sysctl net.ipv4.ip_forward` |
| `tcpdump` | Which packets entered, left, or crossed an interface? | `... exec lab-router tcpdump -i any -nn icmp` |
| `iptables` | Which firewall rules allow or drop packets? | `... exec lab-router iptables -L FORWARD -n -v` |
| `ss` | Which sockets are listening or connected? | `... exec postgres-primary ss -lnt` |
| `curl` | Does an HTTP request reach an application? | `... exec public-a-test curl -sS http://10.10.1.3` |
| `nc` | Can a TCP connection reach a port? | `... exec app-a-test nc -vz 10.10.21.20 5432` |
| `ps` | Which processes are running? | `... exec public-a-test ps` |
| `id` | Which user and groups does the process have? | `... exec app-a-test id` |
| `getent hosts` | Can a name resolve to an address? | `... exec app-a-test getent hosts postgres-primary` |

## Packet-Path Order

When a test fails, inspect the packet path in this order:

```text
process
    |
    v
socket / port
    |
    v
interface and address
    |
    v
route and next hop
    |
    v
neighbor resolution / Ethernet frame
    |
    v
router forwarding
    |
    v
firewall decision
    |
    v
NAT translation, if configured
    |
    v
destination socket and application
```

The commands map to those layers:

```text
ps, id                  process identity and lifecycle
ss                      socket and port
ip addr                 interface and address
ip route / route get    route and next hop
ip neigh                local IP-to-MAC resolution
sysctl                  kernel forwarding behavior
tcpdump                 packet evidence
iptables                firewall decision
conntrack               flow and NAT state
curl, nc, psql          application or port result
```

Do not jump straight to the application layer when the route is missing. Do not
change firewall rules when a packet never selected the correct interface.

# Quick Guide

## Compose Runner

### Start a Stage

```bash
bash scripts/compose-stage.sh 06 up -d
```

Add `--build` when the stage introduces or changes an image:

```bash
bash scripts/compose-stage.sh 06 up -d --build
```

The alternate router-chain lesson uses `05b`:

```bash
bash scripts/compose-stage.sh 05b up -d --build
```

### List Services

```bash
bash scripts/compose-stage.sh 06 ps
```

Use Compose's service list without starting containers:

```bash
bash scripts/compose-stage.sh 06 config --services
```

### Execute in a Running Container

```bash
bash scripts/compose-stage.sh 06 exec app-a-test ip route
```

Open an interactive shell:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test sh
```

`exec` requires a running service. The command after the service name is the
command executed inside that container.

### Run a Temporary Command

```bash
bash scripts/compose-stage.sh 01 run --rm public-a-test true
```

`run` creates a one-off container. It is useful for comparing a command that
exits immediately with a long-running service.

### Recreate a Service

```bash
bash scripts/compose-stage.sh 06 up -d --force-recreate app-a-test
```

Recreation gives the service a new container and network namespace. Runtime
routes, neighbor entries, and firewall changes made inside the old namespace
are lost unless startup configuration reapplies them.

### Inspect Resolved Configuration

```bash
bash scripts/compose-stage.sh 06 config
```

Use this before debugging a running container. It shows the merged result of
the earlier chapter overlays and the requested chapter overlay.

Validate without printing the full document:

```bash
bash scripts/compose-stage.sh 06 config --quiet
```

### Stop a Stage

```bash
bash scripts/compose-stage.sh 06 down
```

Remove volumes only when the lesson explicitly requires a data reset:

```bash
bash scripts/compose-stage.sh 17 down -v
```

## Docker Network Commands

### List Docker Networks

```bash
docker network ls
```

This lists networks known to the Docker daemon. It does not show the routes
inside a container namespace.

### Inspect a Network

```bash
docker network inspect docker-subnet_app_a
```

Useful information includes:

```text
Name
Driver
IPAM subnet and gateway
connected containers
container IP addresses
```

The project prefix can vary. Find the exact name with:

```bash
docker network ls --format '{{.Name}}'
```

### Check for Overlapping Subnets

```bash
docker network inspect $(docker network ls -q) \
  --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

An overlapping subnet owned by another stack can prevent Docker from creating
the lab network or can make a result misleading.

### Inspect a Container

```bash
docker inspect docker-subnet-app-a-test-1
```

Use this when you need Docker-level information such as mounts, capabilities,
network attachments, environment, or the container's PID on the host.

Use `ip addr` and `ip route` when you need the state visible inside the
container's network namespace.

# Linux Network Commands

## `ip addr`

### Quick Use

Show all interfaces and addresses:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip addr
```

Show one interface:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip addr show dev eth0
```

Show a compact summary when full `iproute2` supports it:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip -br addr
```

The compact form is convenient, but `ip addr` is more portable across the
BusyBox and full `iproute2` versions used in the course.

### What It Shows

Typical output contains:

```text
1: lo: <LOOPBACK,UP,LOWER_UP> ...
    inet 127.0.0.1/8 scope host lo

2: eth0@if...: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 10.10.11.10/24 brd 10.10.11.255 scope global eth0
```

Read the output as:

```text
lo
= loopback interface inside this namespace

eth0
= first container-facing network interface

10.10.11.10/24
= address and prefix assigned to the interface

brd 10.10.11.255
= broadcast address for the subnet

scope global
= usable beyond the local host scope
```

The `@if...` suffix identifies the peer interface index on the other side of a
virtual Ethernet pair. It is not part of the interface name you normally use.

### Interpret Interface Flags

Common flags include:

```text
UP
= the interface is administratively enabled

LOWER_UP
= the link has an active lower-layer connection

LOOPBACK
= the interface is the local loopback device

BROADCAST
= the interface supports broadcast frames

MULTICAST
= the interface supports multicast frames
```

An address in `ip addr` proves that an address is configured. It does not prove
that a route exists to a remote destination or that a firewall permits traffic.

### Add and Remove an Address

These commands mutate live state and are included for experiments:

```bash
ip addr add 10.10.99.10/24 dev eth0
ip addr del 10.10.99.10/24 dev eth0
```

The course normally lets Docker Compose assign addresses. Do not add an
address to a lab service unless the exercise asks you to; a recreation removes
the change.

## `ip route`

### Quick Use

Show the route table:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test ip route
```

Ask for the route to one destination:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.22.10
```

Add a route:

```bash
bash scripts/compose-stage.sh 05b exec shell-1 \
  ip route add 10.50.3.0/24 via 10.50.1.2
```

Idempotently add or update a route:

```bash
ip route replace 10.10.12.0/24 via 10.10.11.2
```

Delete a route:

```bash
ip route delete 10.10.12.0/24 via 10.10.11.2
```

### Read a Route Entry

Example:

```text
10.10.12.0/24 via 10.10.11.2 dev eth0 proto static scope link src 10.10.11.10
```

The fields mean:

```text
10.10.12.0/24
= destination network

via 10.10.11.2
= next-hop address

dev eth0
= egress interface

proto static
= route was explicitly configured

scope link
= next hop is on a directly reachable link

src 10.10.11.10
= preferred source address for this route
```

A directly connected route may look like:

```text
10.10.11.0/24 dev eth0 proto kernel scope link src 10.10.11.10
```

`proto kernel` means Linux created the route because an interface received an
address in that subnet.

The Docker default route may look like:

```text
default via 10.10.11.1 dev eth0
```

`default` is equivalent to `0.0.0.0/0`. It matches destinations for which no
more-specific route exists.

### Route Selection

Linux generally prefers the most-specific matching prefix.

Given:

```text
10.10.12.0/24 via 10.10.11.2
10.10.0.0/16 via 10.10.11.3
```

traffic for `10.10.12.10` uses the `/24` route because `/24` is more specific
than `/16`, which is more specific than `/0`.

Use `ip route get` to ask Linux rather than infer the result from the table:

```bash
ip route get 10.10.12.10
```

### `ip route get` Output

Example:

```text
10.10.22.10 via 10.10.11.2 dev eth0 src 10.10.11.10 uid 0
```

This is a decision for one destination, not a dump of every route.

Read it as:

```text
destination = 10.10.22.10
next hop    = 10.10.11.2
interface   = eth0
source      = 10.10.11.10
```

If the output says `via 10.10.11.1`, the specific lab route is absent or did
not match. If it says `Network is unreachable`, there is no usable matching
route at all.

### Valid Next Hops

A next hop must be reachable through the sender's current interfaces.

Valid from `app-a-test`:

```text
10.10.12.0/24 via 10.10.11.2
```

The next hop `10.10.11.2` is on `app_a`, the sender's local network.

Invalid as a first hop from `app-a-test`:

```text
10.10.12.0/24 via 10.10.12.2
```

`10.10.12.2` is the router's address on another network. The sender cannot
resolve it directly with ARP on `app_a`.

### `add` Versus `replace`

`add` expects the route not to exist:

```bash
ip route add 10.10.12.0/24 via 10.10.11.2
```

Running it twice can produce:

```text
RTNETLINK answers: File exists
```

`replace` creates the route if it is absent and updates it if it exists:

```bash
ip route replace 10.10.12.0/24 via 10.10.11.2
```

This makes it useful in Compose commands and entrypoints that may run more than
once.

### Route Changes Are Runtime Changes

```text
ip route add / replace / delete
        |
        v
live namespace state
        |
        v
container recreation removes it
```

To make a route return after recreation, put an idempotent command in Compose
or an entrypoint. Chapter 06 uses a Compose command; later chapters use
entrypoint logic when more setup must be coordinated.

## `ip neigh`

### Quick Use

Show the neighbor table:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
```

Generate local traffic, then inspect it again:

```bash
bash scripts/compose-stage.sh 03 exec app-a-test \
  ping -c 2 10.10.11.1

bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
```

Clear one entry:

```bash
ip neigh del 10.10.11.1 dev eth0
```

The next local packet will need neighbor resolution again.

### What the Table Means

Example:

```text
10.10.11.1 dev eth0 lladdr 02:42:ac:11:00:01 REACHABLE
```

```text
10.10.11.1
= local next-hop IP

dev eth0
= interface used to reach it

lladdr 02:42:...
= Layer-2 MAC address

REACHABLE
= recent reachability evidence is available
```

Common states include:

```text
REACHABLE
= recently confirmed reachable

STALE
= usable information exists but has not been recently confirmed

DELAY
= kernel is waiting before probing

PROBE
= reachability probes are being sent

FAILED
= resolution or reachability failed

INCOMPLETE
= address resolution is still in progress
```

The neighbor table is not a complete device inventory. It contains mappings
that the namespace has learned or attempted to learn on local links.

ARP resolves a local next hop. It does not route a packet between unrelated
subnets.

## `sysctl`

### Read a Kernel Setting

```bash
bash scripts/compose-stage.sh 05 exec lab-router \
  sysctl net.ipv4.ip_forward
```

Expected when forwarding is enabled:

```text
net.ipv4.ip_forward = 1
```

### Change a Runtime Setting

```bash
sysctl -w net.ipv4.ip_forward=0
```

This changes the live namespace only. A container recreation restores the value
from its image or Compose configuration.

The lab configures forwarding declaratively:

```yaml
sysctls:
  net.ipv4.ip_forward: "1"
```

### What Forwarding Controls

With forwarding disabled:

```text
router-generated traffic
may still work

traffic arriving for another host
cannot cross router interfaces
```

With forwarding enabled, the kernel may forward the packet, but routing and
firewall rules must still permit it.

## `ping`

### Quick Use

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

Useful options:

```text
-c 2
= send two requests, then stop

-W 1
= wait up to one second for a reply on implementations that support it

-I eth0
= choose a source interface on implementations that support it
```

The exact timeout flag varies between BusyBox and full `iputils` versions. Use
`ping --help` inside the image if an option is rejected.

### Interpret Results

Successful:

```text
2 packets transmitted, 2 packets received, 0% packet loss
```

This proves an ICMP request and reply completed. It does not prove that TCP
port `5432` or HTTP port `8000` is available.

Common failures:

```text
Network is unreachable
= no usable route was selected

100% packet loss
= packets or replies were lost; inspect route, forwarding, firewall, and return path

Destination Host Unreachable
= a node generated an unreachable response or could not resolve the next hop

Connection refused
= not a ping result; usually means a TCP host answered without a listener
```

## `traceroute`

### Quick Use

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  traceroute -n -m 3 -w 1 10.10.12.10
```

Useful options:

```text
-n
= print addresses without reverse DNS lookups

-m 3
= maximum of three hops

-w 1
= wait one second for each probe on implementations that support it
```

### How It Finds Hops

Traceroute sends probes with controlled IP TTL values:

```text
TTL 1
        -> first router expires the packet
        -> router returns ICMP time exceeded

TTL 2
        -> second router expires the packet
        -> second router returns ICMP time exceeded

larger TTL
        -> destination eventually responds
```

For the standard Chapter 06 topology, a typical path is:

```text
1  10.10.11.2   lab-router
2  10.10.12.10  app-b-test
```

For Chapter 05B, the same style of test exposes multiple routers:

```text
1  10.50.1.2    lab-router-1
2  10.50.2.3    lab-router-2
3  10.50.3.10   shell-3
```

Stars do not always mean the hop is absent. A firewall, missing ICMP response,
or timeout can hide a hop while the packet continues.

`traceroute` is evidence about path behavior, not a replacement for `ip route
get` or a successful application test.

# Packet Observation

## `tcpdump`

### Quick Use

Start a capture in one terminal:

```bash
bash scripts/compose-stage.sh 07 exec lab-router \
  tcpdump -i any -nn icmp
```

Generate traffic in another terminal:

```bash
bash scripts/compose-stage.sh 07 exec public-a-test \
  ping -c 2 10.10.12.10
```

Capture only one interface:

```bash
bash scripts/compose-stage.sh 07 exec lab-router \
  tcpdump -i eth0 -nn -c 10
```

Write a capture to a file:

```bash
bash scripts/compose-stage.sh 07 exec lab-router \
  tcpdump -i any -nn -c 20 -w /tmp/router.pcap
```

Read a capture file inside the same container:

```bash
bash scripts/compose-stage.sh 07 exec lab-router \
  tcpdump -nn -r /tmp/router.pcap
```

### Important Options

```text
-i any
= listen on every interface in the namespace

-i eth0
= listen on one interface

-n
= do not resolve IP addresses to names

-nn
= do not resolve IP addresses or port numbers to names

-e
= include the Ethernet header and MAC addresses

-v / -vv
= increase protocol detail

-c 10
= stop after ten packets

-w file.pcap
= write raw packets to a capture file

-r file.pcap
= read packets from a capture file
```

### Filter Expressions

Capture ICMP:

```bash
tcpdump -i any -nn icmp
```

Capture one host:

```bash
tcpdump -i any -nn host 10.10.12.10
```

Capture one network:

```bash
tcpdump -i any -nn net 10.10.12.0/24
```

Capture TCP port `5432`:

```bash
tcpdump -i any -nn tcp port 5432
```

Capture HTTP traffic but exclude one host:

```bash
tcpdump -i any -nn 'tcp port 80 and not host 10.10.1.10'
```

Combine filters:

```bash
tcpdump -i any -nn 'host 10.10.11.10 and (icmp or tcp port 5432)'
```

Quote compound filters so the shell does not interpret parentheses or operators
before `tcpdump` receives them.

### Read an ICMP Exchange

A capture may contain:

```text
IP 10.10.1.10 > 10.10.12.10: ICMP echo request
IP 10.10.12.10 > 10.10.1.10: ICMP echo reply
```

On a router with two interfaces, the same request may appear twice:

```text
request enters on public_a
request leaves on app_b
reply enters on app_b
reply leaves on public_a
```

The source and destination IP addresses remain the endpoint addresses while the
router forwards the packet. Ethernet source and destination MAC addresses are
rewritten for each local link.

### Capture Limits

`tcpdump` proves that packets were observed at a capture point. It does not
prove that:

```text
the destination application accepted the payload
the return packet followed the expected route
the firewall allowed every packet in the flow
```

If only one side of a conversation appears, compare:

```text
capture interface
source route
router forwarding
firewall policy
destination return route
```

# Firewall Commands

## `iptables`

### Quick Use

List the router's forwarding rules with counters:

```bash
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

Show rules in command form:

```bash
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -S FORWARD
```

Inspect the NAT table:

```bash
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v
```

### Tables and Chains

The main filter table contains:

```text
INPUT
= packets destined for the local container

OUTPUT
= packets generated by the local container

FORWARD
= packets passing through the container between interfaces
```

The `nat` table commonly contains:

```text
PREROUTING
= destination translation before the route decision

POSTROUTING
= source translation after the route decision

OUTPUT
= translation for locally generated packets when applicable
```

The Chapter 08 router experiment focuses on `FORWARD`. The NAT gateway in
Chapter 10 uses `POSTROUTING` for source translation.

### Read a Rule

Example:

```text
ACCEPT  tcp  --  10.10.11.0/24  10.10.21.0/24  tcp dpt:5432
```

Read it as:

```text
action      = ACCEPT
protocol    = tcp
source      = 10.10.11.0/24
destination = 10.10.21.0/24
destination port = 5432
```

With `-v`, packet and byte counters show whether traffic has matched the rule.

### List Rules Safely

```bash
iptables -L FORWARD -n -v --line-numbers
iptables -S FORWARD
iptables -t nat -L -n -v --line-numbers
```

Use `-n` so addresses and ports remain numeric. Name resolution can delay a
listing and can hide the values you are trying to compare.

### Add, Insert, and Delete Rules

Append a rule:

```bash
iptables -A FORWARD -s 10.10.11.0/24 -d 10.10.21.0/24 \
  -p tcp --dport 5432 -j ACCEPT
```

Insert a rule at a specific position:

```bash
iptables -I FORWARD 1 -s 10.10.11.0/24 -d 10.10.21.0/24 \
  -p tcp --dport 5432 -j ACCEPT
```

Delete a rule by its current line number:

```bash
iptables -L FORWARD -n --line-numbers
iptables -D FORWARD 3
```

Delete a rule by repeating its specification:

```bash
iptables -D FORWARD -s 10.10.11.0/24 -d 10.10.21.0/24 \
  -p tcp --dport 5432 -j ACCEPT
```

Rule numbers can change after insertions or deletions. List the chain again
before deleting by number.

### Policy and Rule Order

Show the current policy:

```bash
iptables -L FORWARD -n -v
```

Set a default policy for an experiment:

```bash
iptables -P FORWARD DROP
```

Rule order matters. A packet matches the first applicable rule in the chain.

The common stateful pattern is:

```text
ESTABLISHED,RELATED -> ACCEPT
specific new flows  -> ACCEPT
everything else     -> default DROP
```

An `ESTABLISHED,RELATED` rule permits reply packets for an allowed connection
without requiring a separate rule for every reverse direction.

### Flush and Restore

Flush a chain during the controlled firewall exercise:

```bash
iptables -F FORWARD
```

This removes rules from the live namespace. Restore the Compose-managed policy
by recreating the router:

```bash
bash scripts/compose-stage.sh 08 up -d --force-recreate lab-router
```

Do not flush the host's firewall by accident. Run firewall commands through the
intended container service.

### Firewall Versus Other Failures

```text
Network is unreachable
= route selection problem before firewall inspection

timeout
= could be firewall DROP, missing return route, or an unavailable host

Connection refused
= destination host answered but no process listened on the port

HTTP 4xx / 5xx
= packet reached the HTTP application, which rejected or failed the request
```

Use `ip route get`, `tcpdump`, and counters together. A zero counter on an
allow rule means the traffic did not match that rule; it does not by itself
prove why.

## Conntrack and NAT Inspection

When available in the image, list tracked flows:

```bash
conntrack -L
```

Inspect NAT rules and counters:

```bash
iptables -t nat -L -n -v --line-numbers
```

Routing chooses the egress interface. NAT then rewrites an address or port
according to the translation rules and conntrack state.

# Process, Socket, and Application Commands

## `ps`

List processes inside a container:

```bash
bash scripts/compose-stage.sh 01 exec public-a-test ps
```

The process with PID 1 is the container's main process in its PID namespace.
When PID 1 exits, Docker considers the container stopped.

Inspect the command line of PID 1:

```bash
bash scripts/compose-stage.sh 01 exec public-a-test \
  sh -c 'tr "\\0" " " </proc/1/cmdline; printf "\\n"'
```

## `id`

Show the current user and groups:

```bash
bash scripts/compose-stage.sh 04 exec app-a-test id
```

Typical output:

```text
uid=0(root) gid=0(root) groups=0(root)
```

UID 0 identifies the user as root inside the container. It does not imply that
all Linux capabilities are present.

## `ss`

List listening TCP sockets:

```bash
ss -lnt
```

Useful options:

```text
-l
= listening sockets

-n
= numeric addresses and ports

-t
= TCP sockets

-u
= UDP sockets

-p
= owning process, when permissions and the image support it
```

Examples:

```bash
bash scripts/compose-stage.sh 13 exec postgres-primary ss -lnt
bash scripts/compose-stage.sh 12 exec nginx-a ss -lnt
```

`ss -lnt` answers whether a process is listening. It does not answer whether a
remote route or firewall rule allows a client to reach that listener.

## `nc` / `netcat`

Test whether a TCP port can be reached:

```bash
bash scripts/compose-stage.sh 13 exec app-a-test \
  nc -vz -w 3 10.10.21.20 5432
```

Read the result as:

```text
succeeded
= TCP reached a listener and completed the connection

timed out
= route, firewall, return path, or listener problem

refused
= host was reached but no process accepted the port
```

The exact output varies by the netcat implementation.

## `curl`

Make an HTTP request:

```bash
bash scripts/compose-stage.sh 12 exec public-a-test \
  curl -sS http://10.10.1.3
```

Useful options:

```text
-s
= silent progress output

-S
= show errors even with silent mode

-i
= include response headers

-v
= show request, response, and connection details

--connect-timeout 3
= bound time spent establishing the connection
```

An HTTP response proves that the request reached the web server. A timeout
usually points to network path, firewall, or listener state. An HTTP error
status is an application-level result after the network succeeded.

## `getent hosts`

Resolve a hostname through the container's configured name service:

```bash
bash scripts/compose-stage.sh 11 exec app-a-test \
  getent hosts postgres-primary
```

Inspect the resolver configuration first:

```bash
bash scripts/compose-stage.sh 11 exec app-a-test cat /etc/resolv.conf
```

Docker commonly configures an embedded resolver at `127.0.0.11` for user-defined
networks. Name resolution and IP reachability are separate tests:

```text
IP address works, name fails
= investigate resolver or DNS policy

name resolves, TCP fails
= investigate route, firewall, return path, or listener
```

# Command Deep Dives

## A Route Is More Than an Address

Suppose `app-a-test` sends to `10.10.22.10`.

The source does not put the remote destination's MAC address directly into the
Ethernet frame. It performs these steps:

```text
1. Look up 10.10.22.10 in the route table.
2. Select 10.10.11.2 as the next hop.
3. Confirm 10.10.11.2 is reachable on app_a.
4. Look up 10.10.11.2 in the neighbor table.
5. Send an Ethernet frame to the router's MAC address.
6. Let the router make its own route decision.
```

Inspect each step with:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.22.10

bash scripts/compose-stage.sh 06 exec app-a-test ip neigh
```

## Why the Router Interface Changes Per Subnet

The standard lab router has these addresses:

```text
public_a   10.10.1.2
public_b   10.10.2.2
app_a      10.10.11.2
app_b      10.10.12.2
db_a       10.10.21.2
db_b       10.10.22.2
```

An endpoint sends to the router address on its own network:

```text
app-a-test -> 10.10.11.2 -> remote subnet
app-b-test -> 10.10.12.2 -> remote subnet
db-a-test  -> 10.10.21.2 -> remote subnet
```

The router can then forward through a different interface. This is why the
route on the source and the connected route on the router are both necessary.

## Why `ip route get` Comes Before `ping`

`ping` gives a binary reachability result plus timing. It does not directly show
which route Linux selected.

Run:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.12.10
```

Then test:

```bash
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
```

If the route points to `10.10.11.1` instead of `10.10.11.2`, fix or restore
the route before investigating forwarding or firewall state.

## Why `tcpdump` Uses Two Terminals

Captures observe. They do not generate traffic.

Terminal one:

```bash
bash scripts/compose-stage.sh 07 exec lab-router \
  tcpdump -i any -nn icmp
```

Terminal two:

```bash
bash scripts/compose-stage.sh 07 exec public-a-test \
  ping -c 2 10.10.12.10
```

This separates the observer from the stimulus. Start the capture first so the
first packet is not missed.

## Why `-nn` Matters

Without `-nn`, `tcpdump` may perform reverse DNS and service-name lookups. That
can:

```text
delay output
replace numeric fields with names
make a simple packet harder to compare with route tables
```

The lab uses fixed IP addresses, so numeric output is usually the clearest
evidence.

## Why `FORWARD` Is Not `INPUT`

For a packet from `app-a-test` to `app-b-test`:

```text
source namespace
        |
        v
lab-router receives packet
        |
        +--> FORWARD chain
        |
        v
destination namespace
```

The packet is not addressed to the router itself. It is passing through the
router, so the router's `FORWARD` chain is the relevant filter chain.

A ping sent by the router itself uses its local output path instead. Do not use
a successful router-generated ping as proof that forwarded client traffic is
allowed.

## Why a Port Test Is Different From a Ping

```text
ping
= ICMP reachability

nc -vz
= TCP port reachability

curl
= HTTP request and application response

psql
= PostgreSQL protocol, authentication, and SQL behavior
```

They test progressively higher layers. A successful lower-layer test does not
guarantee success at a higher layer.

# Course Recipes

## Chapter 01: Process Lifecycle

```bash
bash scripts/compose-stage.sh 01 up -d
bash scripts/compose-stage.sh 01 ps
bash scripts/compose-stage.sh 01 exec public-a-test ps
bash scripts/compose-stage.sh 01 exec public-a-test \
  sh -c 'tr "\\0" " " </proc/1/cmdline; printf "\\n"'
```

Question answered:

```text
Which process is PID 1, and what keeps the container alive?
```

## Chapter 02: Bridge Networks

```bash
bash scripts/compose-stage.sh 02 up -d
docker network ls
docker network inspect docker-subnet_app_a
bash scripts/compose-stage.sh 02 exec app-a-test ip addr
bash scripts/compose-stage.sh 02 exec app-a-test ip route
```

Question answered:

```text
Which Layer-2 segments exist, and which local route does each container have?
```

## Chapter 03: Namespaces and Neighbors

```bash
bash scripts/compose-stage.sh 03 exec app-a-test ip addr
bash scripts/compose-stage.sh 03 exec app-a-test ip route
bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
bash scripts/compose-stage.sh 03 exec app-a-test \
  ping -c 2 10.10.11.1
bash scripts/compose-stage.sh 03 exec app-a-test ip neigh
```

Question answered:

```text
How do interfaces, connected routes, ARP, and the neighbor table relate?
```

## Chapter 04: Capabilities

```bash
bash scripts/compose-stage.sh 04 exec app-a-test id
bash scripts/compose-stage.sh 04 exec app-a-test ip route
bash scripts/compose-stage.sh 04 exec app-a-test \
  ip route add 10.10.12.0/24 via 10.10.11.1
```

Question answered:

```text
Why can root still be denied a route change without NET_ADMIN?
```

## Chapter 05: Multi-Homed Router

```bash
bash scripts/compose-stage.sh 05 exec lab-router ip addr
bash scripts/compose-stage.sh 05 exec lab-router ip route
bash scripts/compose-stage.sh 05 exec lab-router \
  sysctl net.ipv4.ip_forward
bash scripts/compose-stage.sh 05 exec lab-router \
  ping -c 2 10.10.12.10
```

Question answered:

```text
Does the router have interfaces, connected routes, and forwarding enabled?
```

## Chapter 05B: Router Chain

```bash
bash scripts/compose-stage.sh 05b exec shell-1 ip route
bash scripts/compose-stage.sh 05b exec lab-router-1 ip route
bash scripts/compose-stage.sh 05b exec shell-1 \
  ip route get 10.50.3.10
bash scripts/compose-stage.sh 05b exec shell-1 \
  traceroute -n -m 5 -w 1 10.50.3.10
```

Question answered:

```text
How does a packet cross more than one router, and where does each next hop come from?
```

## Chapter 06: Static Routes

```bash
bash scripts/compose-stage.sh 06 exec app-a-test ip route
bash scripts/compose-stage.sh 06 exec app-a-test \
  ip route get 10.10.22.10
bash scripts/compose-stage.sh 06 exec app-a-test \
  ping -c 2 10.10.12.10
bash scripts/compose-stage.sh 06 exec app-b-test \
  ip route get 10.10.11.10
```

Question answered:

```text
Are both the forward and return routes present?
```

## Chapter 07: Packet Tracing

```bash
bash scripts/compose-stage.sh 07 exec lab-router \
  tcpdump -i any -nn icmp
```

In a second terminal:

```bash
bash scripts/compose-stage.sh 07 exec public-a-test \
  ping -c 2 10.10.12.10
```

Question answered:

```text
Which router interfaces saw the request and reply?
```

## Chapter 08: Stateful Firewalling

```bash
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
bash scripts/compose-stage.sh 08 exec lab-router \
  iptables -S FORWARD
```

Question answered:

```text
Which forwarding rules matched, and which counters changed?
```

## Chapter 09: Private Networks

```bash
bash scripts/compose-stage.sh 09 config
bash scripts/compose-stage.sh 09 exec app-a-test ip route
docker network inspect docker-subnet_app_a
```

Question answered:

```text
Which networks are marked internal, and which egress path is intentionally absent?
```

## Chapter 10: NAT Gateway

```bash
bash scripts/compose-stage.sh 10 exec app-a-test \
  ip route get 10.10.30.10
bash scripts/compose-stage.sh 10 exec nat-gateway \
  iptables -t nat -L POSTROUTING -n -v
```

Question answered:

```text
Which route selects the NAT gateway, and which rule rewrites the source address?
```

## Chapter 11: Docker DNS

```bash
bash scripts/compose-stage.sh 11 exec app-a-test cat /etc/resolv.conf
bash scripts/compose-stage.sh 11 exec app-a-test \
  getent hosts postgres-primary
bash scripts/compose-stage.sh 11 exec app-a-test \
  getent hosts example.com
```

Question answered:

```text
Is the failure name resolution, IP routing, or application connectivity?
```

## Chapter 12: Nginx Public Access

```bash
bash scripts/compose-stage.sh 12 exec public-a-test \
  curl -sS http://10.10.1.3
bash scripts/compose-stage.sh 12 exec nginx-a nginx -t
bash scripts/compose-stage.sh 12 exec nginx-a ss -lnt
```

Question answered:

```text
Did the public request reach Nginx, and can Nginx reach the app upstream?
```

## Chapters 13-16: Database and Persistence

```bash
bash scripts/compose-stage.sh 13 exec app-a-test \
  nc -vz -w 3 10.10.21.20 5432
bash scripts/compose-stage.sh 13 exec postgres-primary \
  ss -lnt
bash scripts/compose-stage.sh 14 exec postgres-primary ps -ef
bash scripts/compose-stage.sh 16 exec postgres-replica \
  psql -U labadmin -d labdb -c 'SELECT pg_is_in_recovery();'
```

Question answered:

```text
Did the packet reach PostgreSQL, and which database process or recovery state responded?
```

## Chapter 17: Final Checks

```bash
bash scripts/test-routing.sh
bash scripts/test-firewall.sh
bash scripts/test-nat.sh
bash scripts/test-replication.sh
```

Read the test script before running it when you need to know which layer it
asserts.

# Troubleshooting Matrix

| Symptom | First command | Next layer |
|---|---|---|
| Container exits immediately | `... ps`, `... exec ... ps` | PID 1 and command |
| `Network is unreachable` | `ip route get DESTINATION` | Route table |
| Route uses Docker `.1` gateway | `ip route get DESTINATION` | Missing specific route |
| Next hop is on another subnet | `ip route get DESTINATION` | Invalid route design |
| Neighbor is `INCOMPLETE` | `ip neigh`, `tcpdump -i eth0 -nn arp` | Local L2 and gateway |
| Router cannot forward | `sysctl net.ipv4.ip_forward` | Kernel forwarding |
| Ping times out | `tcpdump`, `iptables -L FORWARD -n -v` | Firewall or return path |
| Only request appears in capture | `ip route get` on destination | Return route |
| TCP times out | `nc -vz -w 3 HOST PORT` | Route, firewall, listener |
| TCP is refused | `ss -lnt` on destination | Process or port |
| Hostname fails, IP works | `cat /etc/resolv.conf`, `getent hosts` | DNS |
| HTTP returns an error | `curl -v URL` | Application or proxy |
| Firewall counter stays zero | `iptables -L ... -v` | Rule match and route |
| Route disappears after recreate | `ip route`, `... config` | Startup persistence |
| NAT rule counter stays zero | `ip route get`, `iptables -t nat ...` | Egress route and rule |

## A Repeatable Debugging Loop

Use one destination and test one layer at a time:

```bash
# 1. Is the service running?

# 2. Does the source have the expected address?

# 3. Which route will Linux use?
  ip route get 10.10.12.10

# 4. Can the source reach its local next hop?
  ping -c 2 10.10.11.2

# 5. Is the router forwarding?
  sysctl net.ipv4.ip_forward

# 6. Does the router know the destination?
  ip route get 10.10.12.10

# 7. Is the return route present?
  ip route get 10.10.11.10

# 8. Is a firewall rule dropping the flow?
  iptables -L FORWARD -n -v --line-numbers

# 9. What packets actually moved?
  tcpdump -i any -nn host 10.10.12.10

# 10. Does the application port answer?
  nc -vz -w 3 10.10.21.20 5432
```

Change one layer at a time. Record the output before making the next change.

# Safe Mutation Rules

These commands alter live state:

```bash
ip route add ...
ip route replace ...
ip route delete ...
ip addr add ...
ip addr del ...
sysctl -w ...
iptables -A ...
iptables -I ...
iptables -D ...
iptables -F ...
iptables -P ...
```

Use this pattern:

```text
inspect current state
        |
        v
make one controlled change
        |
        v
run the smallest relevant test
        |
        v
inspect the changed state
        |
        v
recreate the service or restore the rule
```

Prefer idempotent commands in startup configuration:

```bash
ip route replace ...
```

Avoid putting one-off debugging mutations into a Dockerfile. A Dockerfile
builds an image; a Compose command or entrypoint configures runtime state in the
container namespace.

## Reset a Service After an Experiment

For route, neighbor, capability, forwarding, or firewall experiments:

```bash
bash scripts/compose-stage.sh STAGE up -d --force-recreate SERVICE
```

Examples:

```bash
bash scripts/compose-stage.sh 06 up -d --force-recreate app-a-test
bash scripts/compose-stage.sh 08 up -d --force-recreate lab-router
bash scripts/compose-stage.sh 05b up -d --force-recreate lab-router-1
```

If the image or Compose definition changed, include `--build`:

```bash
bash scripts/compose-stage.sh 06 up -d --build --force-recreate app-a-test
```

## Cleanup

Stop the stage you used:

```bash
bash scripts/compose-stage.sh 06 down
```

Do not use broad host cleanup commands such as `docker system prune` during the
course unless you explicitly intend to remove unrelated Docker resources.
