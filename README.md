# Docker Networking VPC Lab

This repository turns `docker-networking-vpc-lab-course.md` into a progressive,
executable course. Each chapter is a directory containing the Compose change
introduced in that chapter and its lesson notes. The course runner layers the
chapter files in order, so chapter 10 includes everything introduced in
chapters 1 through 9.

Start with [`GLOSSARY.md`](GLOSSARY.md) for the lab's routing, firewall, DNS,
NAT, and replication vocabulary. The full audit and its remediations are in
[`COURSE_AUDIT.md`](COURSE_AUDIT.md).

## Introduction

This is a hands-on infrastructure course about building a small,
VPC-style network with Docker. Instead of starting with a finished Compose
file, the learner builds the system one layer at a time and observes what
changes after every step.

The lab begins with a single container and grows into six isolated subnets:
public, application, and database zones across two regions. Along the way, the
learner adds Linux network namespaces, static routes, a multi-homed router,
stateful firewall rules, private networks, a NAT gateway, Docker DNS, Nginx,
PostgreSQL, and physical streaming replication.

The course is about understanding the path a packet takes and the decisions
made at each layer:

```text
process -> interface -> route -> next hop -> forwarding -> firewall -> NAT -> service
```

Every chapter follows a build, predict, test, break, observe, explain, and fix
cycle. Failures are part of the curriculum: a missing return route, a dropped
firewall packet, a broken DNS lookup, or an empty PostgreSQL data directory is
used to develop troubleshooting skills rather than hidden from the learner.

By the end, the learner can explain how a Docker lab maps conceptually to cloud
networking ideas such as VPC subnets, route tables, security controls, NAT
Gateways, public reverse proxies, and cross-zone database standbys.

## Prerequisites

- Docker Engine with Docker Compose v2
- Linux, or a Linux VM capable of running Docker networking capabilities
- Approximately 2 GB of free disk space for images and PostgreSQL volumes

The lab intentionally uses `NET_ADMIN`, `NET_RAW`, packet capture, routing,
and firewall rules. Run it only on a disposable local Docker environment.

## Start a chapter

From the repository root:

```bash
bash scripts/compose-stage.sh 01 up -d --build
bash scripts/compose-stage.sh 01 ps
bash scripts/compose-stage.sh 01 down
```

Replace `01` with any chapter from `01` through `17`. The runner always loads
all earlier chapter files before the requested chapter.

For the final stack:

```bash
bash scripts/compose-stage.sh 17 up -d --build --wait
bash scripts/test-routing.sh
bash scripts/test-firewall.sh
bash scripts/test-nat.sh
bash scripts/test-replication.sh
```

Reset all containers and the lab volume when repeating replication:

```bash
bash scripts/compose-stage.sh 17 down -v
```

## Course progression

| Chapter | Focus | New capability |
|---|---|---|
| 01 | Container process model | PID 1, `sleep`, command lifecycle |
| 02 | CIDR and bridge networks | Six isolated subnets |
| 03 | Network namespaces | Interfaces, routes, and neighbors |
| 04 | Linux capabilities | `CAP_NET_ADMIN` and reusable lab tools |
| 05 | Router container | Multi-homed forwarding node |
| 06 | Static routing | Remote subnet next hops and return paths |
| 07 | Packet tracing | `tcpdump` observations |
| 08 | Stateful firewalling | `iptables`, conntrack, port segmentation |
| 09 | Private networks | Docker `internal: true` networks |
| 10 | NAT gateway | Default routes and MASQUERADE |
| 11 | Docker DNS | Name resolution versus raw IP connectivity |
| 12 | Public reverse proxy | Nginx to app-tier HTTP flow |
| 13 | PostgreSQL primary | Database routing and process startup |
| 14 | PostgreSQL process model | Background processes and job control |
| 15 | Physical replication | Manual `pg_basebackup` and standby mode |
| 16 | Runtime persistence | Idempotent entrypoints and automatic bootstrap |
| 17 | Failure testing | Repeatable checks and cloud/VPC mapping |

## Teaching loop

Every chapter follows the same loop:

```text
build -> predict -> test -> break -> observe -> explain -> fix -> retest
```

Read the chapter README before starting its stack. Do not skip directly to
chapter 17 on the first pass: the final Compose model is intentionally the
result of the earlier experiments.

Each chapter README includes a labeled `diagram.svg` image. The editable
Graphviz source and a PNG version sit beside it; regenerate all three formats
with `bash scripts/generate-diagrams.sh` after changing a diagram.

## Important lab credentials

These credentials are for the local lab only:

| User | Password | Purpose |
|---|---|---|
| `labadmin` | `postgres` | application database login |
| `replicator` | `replica_password` | physical replication |

The original narrative remains available in
`docker-networking-vpc-lab-course.md`; the chapter folders are the maintained
hands-on implementation.

`dockerfile.networklab.yaml` is preserved as the original six-network snapshot
for comparison. It is not used by the cumulative chapter runner.

The lab intentionally uses fixed CIDRs from the curriculum. Before starting a
networked chapter, check for overlapping Docker networks:

```bash
docker network inspect $(docker network ls -q) --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

Stop or remove only the unrelated stack that owns an overlapping network; the
course runner does not remove networks it did not create.
