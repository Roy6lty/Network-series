#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

write_diagram() {
  local chapter="$1"
  local title="$2"
  local chapter_dir="$root_dir/chapters/$chapter"
  mkdir -p "$chapter_dir"

  {
    cat <<EOF
digraph lab {
  graph [rankdir=LR, bgcolor="#ffffff", pad=0.25, nodesep=0.45, ranksep=0.65, fontname="Arial", label="$title", labelloc=t, fontsize=22, fontcolor="#17324d"]
  node [shape=box, style="rounded,filled", fillcolor="#eaf3ff", color="#24527a", fontname="Arial", fontsize=10, margin="0.12,0.08"]
  edge [fontname="Arial", fontsize=9, color="#24527a", arrowsize=0.7]
  legend [shape=note, fillcolor="#fff7d6", color="#9b7b17", label="LEGEND\\nsolid = active data path\\ndashed = blocked or not yet introduced\\ndotted = control, observation, DNS, or process relationship"]
EOF
    cat
    cat <<'EOF'
}
EOF
  } > "$chapter_dir/diagram.dot"

  dot -Tsvg "$chapter_dir/diagram.dot" -o "$chapter_dir/diagram.svg"
  dot -Tpng "$chapter_dir/diagram.dot" -o "$chapter_dir/diagram.png"
}

write_diagram "01-container-process" "Chapter 01 | Container process lifecycle" <<'DOT'
  host [label="Docker host\nLinux kernel", fillcolor="#f2f2f2"]
  container [label="public-a-test\ncontainer namespace\n(no lab network yet)"]
  pid1 [label="PID 1\nsleep infinity\nkeeps container alive", fillcolor="#dff4e5"]
  exit [label="true\nprocess exits\ncontainer stops", style="rounded,dashed,filled", fillcolor="#ffe5e5", color="#a33a3a"]
  host -> container [label="docker compose up", style=solid]
  container -> pid1 [label="exec main process", style=dotted]
  pid1 -> exit [label="replace command", style=dashed, color="#a33a3a"]
  legend -> host [style=invis]
DOT

write_diagram "02-cidr-bridges" "Chapter 02 | Six isolated Docker bridge networks" <<'DOT'
  subgraph cluster_public_a { label="public_a | 10.10.1.0/24 | gw .1"; style="rounded,dashed"; color="#3875a5"; pa [label="public-a-test\n10.10.1.10"] }
  subgraph cluster_public_b { label="public_b | 10.10.2.0/24 | gw .1"; style="rounded,dashed"; color="#3875a5"; pb [label="public-b-test\n10.10.2.10"] }
  subgraph cluster_app_a { label="app_a | 10.10.11.0/24 | bridge"; style="rounded,dashed"; color="#6b8e55"; aa [label="app-a-test\n10.10.11.10"] }
  subgraph cluster_app_b { label="app_b | 10.10.12.0/24 | bridge"; style="rounded,dashed"; color="#6b8e55"; ab [label="app-b-test\n10.10.12.10"] }
  subgraph cluster_db_a { label="db_a | 10.10.21.0/24 | bridge"; style="rounded,dashed"; color="#9b6b55"; da [label="db-a-test\n10.10.21.10"] }
  subgraph cluster_db_b { label="db_b | 10.10.22.0/24 | bridge"; style="rounded,dashed"; color="#9b6b55"; db [label="db-b-test\n10.10.22.10"] }
  aa -> ab [label="no route / no router", style=dashed, color="#a33a3a"]
  pa -> da [label="isolated L2 segments", style=dashed, color="#a33a3a"]
  legend -> pa [style=invis]
DOT

write_diagram "03-network-namespaces" "Chapter 03 | Container network namespace inspection" <<'DOT'
  subgraph cluster_namespace { label="app-a-test network namespace"; style="rounded,dashed"; color="#3875a5"; loop [label="lo\n127.0.0.1"] ; eth0 [label="eth0\n10.10.11.10/24\ncontainer interface"]; routes [label="routing table\nconnected app_a route\nno remote next hop", fillcolor="#fff7d6"]; neigh [label="neighbor table\nARP / IP -> MAC", fillcolor="#fff7d6"]; loop -> eth0 [style=dotted, label="namespace"] ; eth0 -> routes [style=dotted]; eth0 -> neigh [style=dotted] }
  bridge [label="Docker bridge\n10.10.11.1\nLayer-2 segment", fillcolor="#f2f2f2"]
  remote [label="10.10.12.10\nseparate bridge", style="rounded,dashed,filled", fillcolor="#ffe5e5", color="#a33a3a"]
  eth0 -> bridge [label="same subnet", style=solid]
  routes -> remote [label="no usable route", style=dashed, color="#a33a3a"]
  legend -> loop [style=invis]
DOT

write_diagram "04-capabilities" "Chapter 04 | CAP_NET_ADMIN enables network mutation" <<'DOT'
  app [label="app-a-test\nroot inside container\n10.10.11.10"]
  capability [label="NET_ADMIN\ncapability granted\nroute/interface/firewall changes", fillcolor="#dff4e5"]
  route [label="ip route replace\n10.10.12.0/24\nvia 10.10.11.2", fillcolor="#dff4e5"]
  denied [label="without capability\nOperation not permitted", style="rounded,dashed,filled", fillcolor="#ffe5e5", color="#a33a3a"]
  router [label="future lab-router\nnot present yet", style="rounded,dashed,filled", fillcolor="#f2f2f2"]
  app -> capability [label="container root", style=dotted]
  capability -> route [label="authorized mutation", style=solid]
  app -> denied [label="same command without NET_ADMIN", style=dashed, color="#a33a3a"]
  route -> router [label="next hop is introduced later", style=dashed, color="#a33a3a"]
  legend -> app [style=invis]
DOT

write_diagram "05-router-container" "Chapter 05 | Multi-homed Linux router" <<'DOT'
  router [label="lab-router\nNET_ADMIN\nip_forward=1\nconnected routes", fillcolor="#dff4e5", shape=hexagon]
  subgraph cluster_pa { label="public_a\n10.10.1.0/24"; style="rounded,dashed"; pa [label=".2 router\n.10 client"] }
  subgraph cluster_pb { label="public_b\n10.10.2.0/24"; style="rounded,dashed"; pb [label=".2 router\n.10 client"] }
  subgraph cluster_aa { label="app_a\n10.10.11.0/24"; style="rounded,dashed"; aa [label=".2 router\n.10 client"] }
  subgraph cluster_ab { label="app_b\n10.10.12.0/24"; style="rounded,dashed"; ab [label=".2 router\n.10 client"] }
  subgraph cluster_da { label="db_a\n10.10.21.0/24"; style="rounded,dashed"; da [label=".2 router\n.10 client"] }
  subgraph cluster_db { label="db_b\n10.10.22.0/24"; style="rounded,dashed"; db [label=".2 router\n.10 client"] }
  router -> pa [label="eth on public_a", style=solid]; router -> pb [label="eth on public_b", style=solid]; router -> aa [label="eth on app_a", style=solid]; router -> ab [label="eth on app_b", style=solid]; router -> da [label="eth on db_a", style=solid]; router -> db [label="eth on db_b", style=solid]
  legend -> router [style=invis]
DOT

write_diagram "06-static-routing" "Chapter 06 | Static routes and return paths" <<'DOT'
  source [label="public-a-test\n10.10.1.10\nroute: db_b via 10.10.1.2"]
  router [label="lab-router\n10.10.1.2 <-> 10.10.22.2\nip_forward=1", fillcolor="#dff4e5", shape=hexagon]
  target [label="db-b-test\n10.10.22.10\nroute: public_a via 10.10.22.2"]
  forward [label="forward path\npublic_a -> router -> db_b", fillcolor="#dff4e5"]
  return_path [label="return path\ndb_b -> router -> public_a", fillcolor="#dff4e5"]
  missing [label="missing return route\nTCP hangs / replies lost", style="rounded,dashed,filled", fillcolor="#ffe5e5", color="#a33a3a"]
  source -> router [label="10.10.22.0/24 via .1.2", style=solid]
  router -> target [label="connected db_b route", style=solid]
  target -> router [label="10.10.1.0/24 via .22.2", style=solid]
  router -> source [label="reply", style=solid]
  forward -> source [style=dotted]; return_path -> target [style=dotted]
  target -> missing [label="if return route deleted", style=dashed, color="#a33a3a"]
  legend -> source [style=invis]
DOT

write_diagram "07-packet-tracing" "Chapter 07 | tcpdump sees both router interfaces" <<'DOT'
  client [label="public-a-test\n10.10.1.10\nICMP echo request"]
  ingress [label="router ingress\npublic_a eth\n10.10.1.2", fillcolor="#fff7d6"]
  router [label="lab-router\nforwarding decision", shape=hexagon, fillcolor="#dff4e5"]
  egress [label="router egress\napp_b eth\n10.10.12.2", fillcolor="#fff7d6"]
  server [label="app-b-test\n10.10.12.10\nICMP echo reply"]
  capture [label="tcpdump -i any -nn icmp\nobserves ingress + egress", fillcolor="#f2f2f2"]
  client -> ingress [label="echo request", style=solid]; ingress -> router [style=solid]; router -> egress [style=solid]; egress -> server [label="forwarded request", style=solid]
  server -> egress [label="reply", style=solid]; egress -> router [style=solid]; router -> ingress [style=solid]; ingress -> client [label="reply delivered", style=solid]
  capture -> router [label="observation only", style=dotted]
  legend -> client [style=invis]
DOT

write_diagram "08-iptables-firewall" "Chapter 08 | Stateful FORWARD firewall" <<'DOT'
  public [label="public_a\n10.10.1.0/24\nclient"]
  router [label="lab-router\nFORWARD policy DROP\nconntrack state", shape=hexagon, fillcolor="#fff7d6"]
  app [label="app_a\n10.10.11.0/24\nTCP 8000"]
  db [label="db_a\n10.10.21.0/24\nTCP 5432"]
  blocked [label="app_b\n10.10.12.0/24\nTCP 8000", style="rounded,dashed,filled", fillcolor="#ffe5e5", color="#a33a3a"]
  established [label="ESTABLISHED,RELATED\nreturn packets accepted", fillcolor="#dff4e5"]
  public -> router [label="new TCP 8000", style=solid]; router -> app [label="explicit allow", style=solid]
  app -> router [label="new TCP 5432", style=solid]; router -> db [label="explicit allow", style=solid]
  router -> established [label="state match", style=dotted]; established -> public [label="reverse traffic", style=solid]
  router -> blocked [label="no matching rule = DROP", style=dashed, color="#a33a3a"]
  legend -> public [style=invis]
DOT

write_diagram "09-private-networks" "Chapter 09 | Internal application and database bridges" <<'DOT'
  public [label="public_a / public_b\nreachable public zones"]
  router [label="lab-router\nexplicit inter-subnet path", shape=hexagon, fillcolor="#dff4e5"]
  app [label="app_a + app_b\ninternal: true\nno normal Docker host egress", fillcolor="#fff7d6"]
  db [label="db_a + db_b\ninternal: true\nprivate data zones", fillcolor="#fff7d6"]
  host [label="Docker host / internet\nnot directly attached", style="rounded,dashed,filled", fillcolor="#ffe5e5", color="#a33a3a"]
  public -> router [label="routed lab traffic", style=solid]; router -> app [style=solid]; router -> db [style=solid]
  app -> host [label="internal bridge blocks normal egress", style=dashed, color="#a33a3a"]
  db -> host [label="internal bridge blocks normal egress", style=dashed, color="#a33a3a"]
  legend -> public [style=invis]
DOT

write_diagram "10-nat-gateway" "Chapter 10 | NAT gateway and MASQUERADE" <<'DOT'
  app [label="app-a-test\n10.10.11.10:40000\ndefault via 10.10.11.3"]
  nat [label="nat-gateway\napp_a .11.3\napp_b .12.3\nnat_public .30.2\nIP forwarding + conntrack", shape=hexagon, fillcolor="#fff7d6"]
  public [label="nat_public\n10.10.30.0/24\nobserver .30.10:8080"]
  host [label="Docker host / upstream\npublic-side next hop"]
  before [label="before NAT\nsrc 10.10.11.10:40000\ndst 10.10.30.10:8080", fillcolor="#eaf3ff"]
  after [label="after MASQUERADE\nsrc 10.10.30.2:40000\ndst 10.10.30.10:8080", fillcolor="#dff4e5"]
  app -> nat [label="route chooses NAT", style=solid]; nat -> public [label="MASQUERADE on egress", style=solid]; public -> host [label="optional external egress", style=solid]
  before -> nat [label="packet enters", style=dotted]; nat -> after [label="source rewrite", style=dotted]
  public -> nat [label="conntrack restores private destination", style=solid]
  app -> host [label="direct private egress blocked", style=dashed, color="#a33a3a"]
  legend -> app [style=invis]
DOT

write_diagram "11-docker-dns" "Chapter 11 | Docker embedded DNS versus raw IP" <<'DOT'
  app [label="app-a-test\napplication\nraw IP works"]
  resolver [label="127.0.0.11\nDocker embedded DNS", fillcolor="#fff7d6"]
  service [label="postgres-primary\nservice-name lookup\nshared-network answer", fillcolor="#dff4e5"]
  upstream [label="upstream resolver\nexample.com", fillcolor="#f2f2f2"]
  ip [label="10.10.21.20\nroute + TCP test", fillcolor="#eaf3ff"]
  app -> ip [label="direct address", style=solid]
  app -> resolver [label="hostname query", style=dotted]
  resolver -> service [label="Docker service discovery", style=dotted]
  resolver -> upstream [label="external DNS forwarding", style=dotted]
  app -> upstream [label="if DNS path is broken", style=dashed, color="#a33a3a"]
  legend -> app [style=invis]
DOT

write_diagram "12-nginx-public-access" "Chapter 12 | Public Nginx reverse proxy to private app" <<'DOT'
  client [label="public-a-test\n10.10.1.10\nHTTP :80"]
  nginx [label="nginx-a\n10.10.1.3\npublic listener :80\nupstream route via .1.2", fillcolor="#fff7d6"]
  router [label="lab-router\nFORWARD TCP 8000", shape=hexagon, fillcolor="#dff4e5"]
  app [label="app-a-test\n10.10.11.10\nPython HTTP :8000"]
  session1 [label="TCP session 1\nclient <-> nginx", fillcolor="#eaf3ff"]
  session2 [label="TCP session 2\nnginx <-> app", fillcolor="#eaf3ff"]
  client -> nginx [label="HTTP request :80", style=solid]; nginx -> router [label="new upstream TCP :8000", style=solid]; router -> app [style=solid]; app -> router [label="HTTP response", style=solid]; router -> nginx [style=solid]; nginx -> client [label="proxy response", style=solid]
  session1 -> client [style=dotted]; session2 -> router [style=dotted]
  legend -> client [style=invis]
DOT

write_diagram "13-postgres-primary" "Chapter 13 | Routed application to PostgreSQL primary" <<'DOT'
  app [label="app-a-test\n10.10.11.10\nclient TCP :5432"]
  router [label="lab-router\napp_a .11.2\ndb_a .21.2\nFORWARD allow :5432", shape=hexagon, fillcolor="#dff4e5"]
  db [label="postgres-primary\n10.10.21.20:5432\nread/write primary", fillcolor="#fff7d6"]
  route [label="primary return route\n10.10.11.0/24 via 10.10.21.2", fillcolor="#eaf3ff"]
  hba [label="pg_hba.conf\napplication/auth policy\nafter network firewall", fillcolor="#f2f2f2"]
  app -> router [label="NEW TCP :5432", style=solid]; router -> db [label="FORWARD allow", style=solid]; db -> router [label="reply via return route", style=solid]; router -> app [style=solid]
  db -> hba [label="PostgreSQL accepts/rejects", style=dotted]
  route -> db [style=dotted]
  legend -> app [style=invis]
DOT

write_diagram "14-postgres-process-model" "Chapter 14 | PostgreSQL process tree inside a container" <<'DOT'
  client [label="client session\napp or psql"]
  pid1 [label="postgres main\ncontainer PID 1\nlistens on :5432", fillcolor="#dff4e5"]
  backend [label="client backend\none OS process per session"]
  workers [label="background workers\ncheckpointer\nwalwriter\nautovacuum", fillcolor="#fff7d6"]
  shell [label="shell job control\nCtrl-Z / bg / fg\njobs", fillcolor="#f2f2f2"]
  client -> pid1 [label="TCP / Unix socket", style=solid]
  pid1 -> backend [label="forks session backend", style=dotted]
  pid1 -> workers [label="supervises workers", style=dotted]
  shell -> pid1 [label="do not background DB itself", style=dashed, color="#a33a3a"]
  legend -> client [style=invis]
DOT

write_diagram "15-physical-replication" "Chapter 15 | Manual physical standby bootstrap" <<'DOT'
  app [label="app_a / app_b\nclients\nwrite to primary"]
  primary [label="postgres-primary\n10.10.21.20\nwrite + WAL source", fillcolor="#dff4e5"]
  router [label="lab-router\ndb_a .21.2\ndb_b .22.2\nTCP :5432 allowed", shape=hexagon, fillcolor="#fff7d6"]
  replica [label="postgres-replica\n10.10.22.20\nread-only standby", fillcolor="#eaf3ff"]
  basebackup [label="pg_basebackup\nphysical cluster copy\n-R creates standby.signal", fillcolor="#f2f2f2"]
  app -> primary [label="application TCP :5432", style=solid]
  primary -> router [label="replication connection", style=solid]; router -> replica [label="db_b destination", style=solid]
  replica -> router [label="WAL stream request", style=solid]; router -> primary [label="db_a destination", style=solid]
  primary -> replica [label="WAL replay / read-only state", style=solid]
  basebackup -> replica [label="initial population", style=dotted]
  legend -> app [style=invis]
DOT

write_diagram "16-runtime-persistence" "Chapter 16 | Entrypoint persistence and replica bootstrap" <<'DOT'
  docker [label="Docker starts\nreplica container"]
  wrapper [label="lab-entrypoint.sh\nroute replace\nwait for primary\nbasebackup if PGDATA empty", fillcolor="#fff7d6"]
  official [label="docker-entrypoint.sh\ninitialization delegation", fillcolor="#eaf3ff"]
  postgres [label="postgres PID 1\nstandby.signal\nread-only recovery", fillcolor="#dff4e5"]
  volume [label="postgres_replica_data\nPGDATA persists across restart", fillcolor="#f2f2f2"]
  primary [label="primary 10.10.21.20\nWAL source"]
  docker -> wrapper [label="ENTRYPOINT", style=solid]; wrapper -> official [label="exec", style=solid]; official -> postgres [label="exec postgres", style=solid]; postgres -> volume [label="cluster state", style=dotted]
  wrapper -> primary [label="basebackup / readiness", style=dotted]
  wrapper -> volume [label="skip bootstrap when PG_VERSION exists", style=dashed, color="#a33a3a"]
  legend -> docker [style=invis]
DOT

write_diagram "17-failure-testing" "Chapter 17 | Final VPC-style lab and failure boundaries" <<'DOT'
  public [label="public_a + public_b\n10.10.1.0/24\n10.10.2.0/24\nNginx .3", fillcolor="#eaf3ff"]
  router [label="lab-router\ninter-subnet routes\nFORWARD default DROP", shape=hexagon, fillcolor="#fff7d6"]
  apps [label="app_a + app_b\n10.10.11.0/24\n10.10.12.0/24\nprivate HTTP", fillcolor="#dff4e5"]
  nat [label="nat-gateway\n.11.3 / .12.3 / .30.2\nMASQUERADE", shape=hexagon, fillcolor="#fff7d6"]
  primary [label="db_a\npostgres-primary\n10.10.21.20\nread/write", fillcolor="#eaf3ff"]
  replica [label="db_b\npostgres-replica\n10.10.22.20\nread-only standby", fillcolor="#eaf3ff"]
  internet [label="Docker host / internet\nNAT egress", fillcolor="#f2f2f2"]
  public -> router [label="allowed public paths", style=solid]; router -> apps [label="TCP 8000", style=solid]; apps -> router [label="TCP 5432", style=solid]; router -> primary [style=solid]; apps -> nat [label="default route", style=solid]; nat -> internet [label="source translated", style=solid]; replica -> router [label="replication TCP 5432", style=solid]; router -> primary [label="WAL stream", style=solid]
  public -> primary [label="segmentation / DROP", style=dashed, color="#a33a3a"]; primary -> internet [label="private DB no direct egress", style=dashed, color="#a33a3a"]
  legend -> public [style=invis]
DOT

printf 'Generated chapter diagrams under %s/chapters.\n' "$root_dir"
