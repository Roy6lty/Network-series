# Chapter 02: CIDR and Bridge Networks

![Chapter 02 six bridge networks](diagram.svg)

## Key concepts

- **CIDR** describes the network prefix and host bits; `/24` gives this lab 256
  addresses, including network and broadcast reservations.
- A **user-defined bridge** is a Docker-managed Layer-2 segment.
- **IPAM** assigns the fixed addresses declared in Compose; this is not DHCP.
- The Docker `.1` address is the bridge gateway. It is not the lab router `.2`.

## Goal

Create six user-defined bridge networks with explicit `/24` CIDRs and fixed
container addresses.

## Adds

The seed service is attached to `public_a`; five diagnostic services and the
remaining five subnets are added. No router exists yet, so the networks are
isolated from one another.

## Checkpoint

```bash
bash scripts/compose-stage.sh 02 up -d
bash scripts/compose-stage.sh 02 exec public-a-test ip -br addr
bash scripts/compose-stage.sh 02 exec app-a-test ip route
```

Confirm that `10.10.11.10` and `10.10.12.10` are on different L2 networks and
that a direct ping between them cannot work.

Expected observation: each container has a connected route for its local `/24`,
but no route that points at the other bridge. A failed ping here proves
isolation, not that either container is unhealthy.

## Break it

Try `bash scripts/compose-stage.sh 02 exec app-a-test ping -c 2 10.10.12.10`.
The failure is expected because a route and a forwarding device do not exist.

Clean up with `bash scripts/compose-stage.sh 02 down` when the experiment is
complete.
