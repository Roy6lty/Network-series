# Lab Glossary And Diagram Guide

## Diagram notation

Every chapter contains three equivalent diagram forms:

- `diagram.dot`: editable Graphviz source;
- `diagram.svg`: scalable image for documentation;
- `diagram.png`: raster image for slides or offline notes.

The edge styles are intentional:

| Style | Meaning |
|---|---|
| Solid arrow | Active data path permitted by the current chapter |
| Dashed arrow | Blocked, missing, or not-yet-introduced data path |
| Dotted arrow | Control, observation, name-resolution, or process relationship |
| Dashed network border | An isolated/private boundary or a conceptual zone |

An arrow describes packet direction, not ownership. A return arrow is shown
where the return path is part of the lesson.

## Docker bridge and VPC limits

The lab uses user-defined Docker bridge networks. A bridge supplies a local
Layer-2 segment, a virtual Ethernet attachment for each container, and Docker
IPAM addresses. The six lab CIDRs are:

| Network | CIDR | Docker gateway | Router address |
|---|---|---:|---:|
| `public_a` | `10.10.1.0/24` | `10.10.1.1` | `10.10.1.2` |
| `public_b` | `10.10.2.0/24` | `10.10.2.1` | `10.10.2.2` |
| `app_a` | `10.10.11.0/24` | `10.10.11.1` | `10.10.11.2` |
| `app_b` | `10.10.12.0/24` | `10.10.12.1` | `10.10.12.2` |
| `db_a` | `10.10.21.0/24` | `10.10.21.1` | `10.10.21.2` |
| `db_b` | `10.10.22.0/24` | `10.10.22.1` | `10.10.22.2` |

The cloud analogy is useful but bounded: a Docker bridge is not a cloud VPC,
Docker `internal: true` is not a complete security boundary, and an iptables
rule is not identical to a cloud security group or network ACL.

## CIDR, interface, and gateway

`10.10.11.0/24` means 24 network bits and 8 host bits. The usable host range
is normally `10.10.11.1` through `10.10.11.254`; this lab reserves `.1` for the
Docker bridge gateway, `.2` for the lab router, and `.10` for the diagnostic
app.

An interface is the attachment point visible inside a network namespace. A
gateway is a next-hop IP on the sender's local subnet. A sender cannot use
`10.10.12.2` as a next hop while attached only to `10.10.11.0/24`; it must use
the router's local address `10.10.11.2`.

## Namespace, route, neighbor, and forwarding

- A **network namespace** owns interfaces, routes, neighbors, and firewall
  state for a process tree.
- A **routing table** answers “which interface and next hop should receive this
  packet?”
- A **neighbor table** maps a local next-hop IP to a Layer-2 MAC address using
  ARP for IPv4.
- **IPv4 forwarding** allows a Linux kernel to move a packet between two of its
  interfaces. An endpoint can have routes without forwarding traffic for
  another endpoint.

The core model is:

```text
route table = where the packet goes
neighbor    = which local MAC receives the frame
forwarding  = whether the kernel routes between interfaces
firewall    = whether the forwarded packet is allowed
NAT         = whether an address/port is rewritten
```

## Firewall layers

| Layer | Question answered | Lab example |
|---|---|---|
| Route table | Where should the packet go? | `ip route get 10.10.21.20` |
| Router `FORWARD` | May a packet cross router interfaces? | Allow app CIDR to TCP `5432` |
| Container `INPUT`/`OUTPUT` | May the local container receive/send? | A router endpoint rule |
| PostgreSQL `pg_hba.conf` | Will PostgreSQL accept an authenticated session? | Allow replication role from `db_b` |

`FORWARD DROP` does not mean a service is down. It means the packet was
discarded before the destination application could answer. `Connection
refused` usually means the destination host answered but no process listened.

## NAT gateway: packet-level definition

A NAT gateway is a router with a translation table. In this lab the app sends
traffic through `10.10.11.3` or `10.10.12.3`; the NAT container forwards it to
`nat_public` at `10.10.30.2`.

Example request before translation:

```text
source      10.10.11.10:40000
destination 10.10.30.10:8080
egress      app_a -> nat-gateway -> nat_public
```

After the `POSTROUTING MASQUERADE` rule:

```text
source      10.10.30.2:40000
destination 10.10.30.10:8080
translation 10.10.11.10:40000 <-> 10.10.30.2:40000
```

The destination sees the NAT gateway's public-side address, not the private
app address. When the reply returns to `10.10.30.2:40000`, conntrack looks up
the translation and restores the destination to `10.10.11.10:40000`.

Three rules must all be true:

1. The app route chooses the NAT gateway as its default next hop.
2. The NAT gateway route chooses `nat_public` as its egress interface.
3. The NAT table rewrites the private source and conntrack permits the reply.

NAT does not choose an interface. Routing does. NAT is not a replacement for
the firewall, and MASQUERADE does not make an otherwise unreachable network
reachable by itself.

`MASQUERADE` discovers the current egress address and is convenient for a
dynamic interface. `SNAT --to-source <address>` is explicit and preferable
when the egress address is stable.

## DNS and service discovery

For a user-defined Docker network, a typical resolution path is:

```text
application -> 127.0.0.11 -> Docker embedded DNS -> upstream resolver
```

Docker's embedded DNS can answer service names such as `postgres-primary` when
the querying container and target share a Docker network. It is not the same
as the upstream resolver used for names such as `example.com`.

| Observation | First layer to investigate |
|---|---|
| IP and hostname both fail | Route, firewall, service, or return path |
| IP works but hostname fails | Resolver, DNS route, or DNS policy |
| Name resolves but TCP times out | Route, firewall, or return path |
| TCP connects but application rejects | Application authentication/configuration |

## Reverse proxy and TCP sessions

Nginx is an application-layer reverse proxy. A request through `nginx-a` has
two TCP sessions:

```text
public client <-> nginx-a:80
nginx-a       <-> app-a:8000
```

Nginx terminates the first session and creates the second. The router's
`FORWARD` rule applies to the Nginx-to-app session, not to an imaginary single
end-to-end TCP connection.

## PostgreSQL replication terms

- **Primary**: the writable PostgreSQL cluster that generates WAL.
- **Standby/replica**: a cluster in recovery that replays the primary's WAL and
  is read-only for this lab.
- **WAL**: write-ahead log records describing durable database changes.
- **`pg_basebackup`**: the initial physical copy of the whole cluster.
- **Streaming replication**: continuous transfer and replay of WAL after the
  base backup.
- **`pg_hba.conf`**: PostgreSQL connection policy; it is not the network
  firewall.

## Runtime persistence

`ip route replace` and `iptables -A` change live namespace/kernel state. A
container recreation can erase those changes. A Dockerfile persists binaries,
Compose persists capabilities and attachments, and an entrypoint reapplies
idempotent runtime state before `exec` starts the real application.

`exec` matters because it replaces the wrapper process. PostgreSQL or Nginx
then becomes the container's signal-receiving PID 1 rather than a child hidden
behind a shell.
