# Chapter 11: Docker DNS

![Chapter 11 Docker DNS resolution paths](diagram.svg)

## Key Concepts

### DNS is a name lookup

DNS answers a question of this form:

```text
What IP address is associated with this name?
```

It does not prove that the resulting address is routable, that a firewall will
allow traffic, that a TCP port is listening, or that an application will accept
the request.

### Docker's embedded resolver

Containers on a user-defined Docker network normally receive a resolver entry
like this:

```text
nameserver 127.0.0.11
```

`127.0.0.11` is Docker's embedded DNS endpoint as seen from the container's
network namespace. A typical lookup path is:

```text
application
    |
    v
127.0.0.11
    |
    v
Docker embedded DNS
    |
    +--> service name on a shared Docker network
    |
    +--> upstream resolver for an external name
```

### Service discovery is network-scoped

Docker can resolve a Compose service name only where the querying container and
the target service share a Docker network. A service name is not a global DNS
record, and resolving a name does not make two isolated networks connected.

### DNS, routes, and TCP are different layers

Keep these checks separate:

```text
getent hosts NAME       = can the name become an IP address?
ip route get IP         = which interface and next hop would Linux use?
nc or curl              = can a TCP connection reach a listening service?
```

For example, a name can fail to resolve while a direct IP request succeeds. In
that case, investigate the resolver first, not the route.

## Goal

Use Docker's embedded DNS in the cumulative Chapter 11 stack, then compare a
service-name lookup with a direct IP request and an external DNS lookup.

By the end, you should be able to:

- find the resolver configured inside a container;
- identify which services share a Docker network;
- distinguish name resolution from route selection;
- distinguish DNS failure from TCP or application failure;
- explain why `127.0.0.11` is not a route between Docker networks.

## From Chapter 10

Chapter 10 added the `nat-gateway` and gave the application containers a
default route for controlled egress. The Chapter 11 Compose file adds no
services; it uses that existing topology.

The stage runner is cumulative. Chapter 11 includes chapters 01 through 10,
but it does not include the PostgreSQL service introduced in Chapter 13. The
service names available here include:

```text
app-a-test       10.10.11.10 on app_a
app-b-test       10.10.12.10 on app_b
lab-router       10.10.11.2 on app_a, among other interfaces
nat-gateway      10.10.11.3 on app_a and 10.10.12.3 on app_b
nat-public-test  10.10.30.10 on nat_public
```

`nat-public-test` is deliberately not on `app_a`. That gives us a useful test
of network-scoped service discovery.

The diagram also previews `postgres-primary`, which is introduced in Chapter
13. Do not run a Chapter 11 command for that service: it is not in the Chapter
11 Compose graph. When Chapter 13 is active, the accurate scope comparison is:

```bash
bash scripts/compose-stage.sh 13 exec db-a-test \
  getent hosts postgres-primary

bash scripts/compose-stage.sh 13 exec app-a-test \
  sh -c 'getent hosts postgres-primary || true'
```

The first lookup works because both services share `db_a`; the second has no
answer because `app-a-test` reaches the database through routing rather than a
shared Docker network. The database can still be tested by its address,
`10.10.21.20`, after Chapter 13 starts it.

## What This Stage Adds

No new container, network, route, or DNS server is added. This stage makes an
existing control path observable:

```text
app-a-test
    |
    +--> 127.0.0.11 --> Docker embedded DNS --> service name lookup
    |
    +--> route table --> nat-gateway --> nat_public --> nat-public-test
```

The raw IP path to `10.10.30.10` already depends on the Chapter 10 route and
NAT configuration. The DNS lookup and the HTTP request are separate tests.

## Progress

- [ ] I can identify Docker's resolver in `/etc/resolv.conf`.
- [ ] I can explain why `lab-router` resolves from `app-a-test`.
- [ ] I can explain why `nat-public-test` does not resolve from `app-a-test`.
- [ ] I can separate a DNS result from a route and TCP result.
- [ ] I can break and restore one container's resolver without changing the host.

## Tasks

### 1. Start the cumulative stage

**Predict:** Chapter 11 has an empty Compose overlay, so the topology should
look like Chapter 10. You should see the six diagnostic services, `lab-router`,
`nat-gateway`, and `nat-public-test`.

**Run:**

```bash
bash scripts/compose-stage.sh 11 up -d --build
bash scripts/compose-stage.sh 11 ps
```

**Observe:** Confirm that `app-a-test`, `lab-router`, `nat-gateway`, and
`nat-public-test` are running. `app-a-test` is the learner's vantage point for
the next tasks.

**Explain:** The runner loads every numbered Compose overlay through 11. An
empty overlay is still a useful chapter because the lesson can inspect the
state built by earlier stages.

### 2. Inspect the resolver and shared-network names

**Predict:** `/etc/resolv.conf` should point at Docker's embedded resolver.
`lab-router` and `nat-gateway` should resolve from `app-a-test` because both
services share `app_a`. `nat-public-test` should not resolve because it is only
on `nat_public`.

**Run:**

```bash
bash scripts/compose-stage.sh 11 exec app-a-test cat /etc/resolv.conf
bash scripts/compose-stage.sh 11 exec app-a-test getent hosts lab-router
bash scripts/compose-stage.sh 11 exec app-a-test getent hosts nat-gateway
bash scripts/compose-stage.sh 11 exec app-a-test \
  sh -c 'getent hosts nat-public-test || true'
```

**Observe:** The resolver output should include:

```text
nameserver 127.0.0.11
```

The service lookups should return addresses similar to:

```text
10.10.11.2  lab-router
10.10.11.3  nat-gateway
```

The lookup for `nat-public-test` should produce no answer. The `|| true` keeps
this expected negative lookup from stopping the terminal command.

**Explain:** Docker DNS has a network view. It can answer for an attached
service, but it does not advertise every service in the Compose project to
every container. This is a DNS scope rule, not a Layer-3 routing rule.

### 3. Compare DNS, routing, and a TCP request

**Predict:** A direct request to `10.10.30.10:8080` should work through the
Chapter 10 NAT path even though `nat-public-test` did not resolve from
`app-a-test`. An external name may resolve through an upstream resolver, but
that result is environment-dependent.

**Run:**

```bash
bash scripts/compose-stage.sh 11 exec app-a-test \
  ip route get 10.10.30.10

bash scripts/compose-stage.sh 11 exec app-a-test \
  curl -sS --connect-timeout 3 http://10.10.30.10:8080/

bash scripts/compose-stage.sh 11 exec app-a-test \
  sh -c 'getent hosts example.com || true'
```

**Observe:** The route lookup should select `10.10.11.3` as the next hop for
`10.10.30.10`. The HTTP request should return the Python server's directory
listing or HTML response. The `example.com` lookup may return one or more
upstream addresses, or it may fail if this Docker environment has no external
DNS or Internet access.

**Explain:** The sequence is:

```text
hostname lookup (optional)
        |
        v
destination IP
        |
        v
route selection
        |
        v
TCP connection and application request
```

`getent hosts` stops after the name-to-address step. `curl` tests the route,
firewall, NAT path, TCP listener, and HTTP response. Neither command replaces
the other.

## Expected Observations

| Test | What it demonstrates |
|---|---|
| `cat /etc/resolv.conf` | The container uses Docker's `127.0.0.11` resolver. |
| `getent hosts lab-router` | A shared-network service name resolves to `10.10.11.2`. |
| `getent hosts nat-public-test` from `app-a-test` | A service on another isolated network is not in this DNS view. |
| `ip route get 10.10.30.10` | The route selects `nat-gateway` at `10.10.11.3`. |
| `curl http://10.10.30.10:8080/` | The raw IP route and TCP/HTTP path work independently of service-name lookup. |

The key model is:

```text
DNS       = what address does this name mean?
route     = where does Linux send that address?
TCP       = can a connection reach a listener?
application = does the listener accept the request?
```

## Checkpoint: Definition of Done

You are done when you can answer all of these without guessing:

1. Why does `app-a-test` use `127.0.0.11`?
2. Why can it resolve `nat-gateway` but not `nat-public-test`?
3. Which command tests route selection rather than DNS?
4. Which command proves that the HTTP service responded?
5. Why does a successful DNS answer not prove that a TCP connection will work?

The progress checklist should now be complete, and the raw IP request should
have been considered separately from every name lookup.

## Break It

Break only the resolver inside `app-a-test`. Do not edit the host resolver or a
Compose file.

**Predict:** A known IP should remain usable, but a service-name lookup should
fail while the bad nameserver is configured.

**Run:**

```bash
bash scripts/compose-stage.sh 11 exec app-a-test sh -c \
  'cp /etc/resolv.conf /tmp/resolv.conf.good; \
   printf "nameserver 192.0.2.1\n" > /etc/resolv.conf; \
   cat /etc/resolv.conf'

bash scripts/compose-stage.sh 11 exec app-a-test \
  sh -c 'getent hosts lab-router || true'

bash scripts/compose-stage.sh 11 exec app-a-test \
  curl -sS --connect-timeout 3 http://10.10.30.10:8080/
```

**Observe:** `lab-router` should no longer resolve through the deliberately
invalid nameserver, while the direct IP request can still use the existing
route and NAT path.

**Explain:** The failure is in name resolution. The IP route and HTTP listener
were not changed. Recreating the container restores Docker's generated
resolver configuration and removes the temporary file with the old namespace.

**Recover:**

```bash
bash scripts/compose-stage.sh 11 up -d --force-recreate app-a-test
bash scripts/compose-stage.sh 11 exec app-a-test cat /etc/resolv.conf
bash scripts/compose-stage.sh 11 exec app-a-test getent hosts lab-router
```

## Clean Up

Remove the resources for this cumulative stage when finished:

```bash
bash scripts/compose-stage.sh 11 down
```

This removes the containers and networks created by the lab. It does not modify
the host's DNS configuration.

## Conclusion: Next Chapter

Docker DNS supplies names for services on shared networks, but it does not
create routes, proxies, or application connections. The next chapter adds
`nginx-a` and `nginx-b` as public HTTP reverse proxies. You will follow two
separate TCP connections: the public client to Nginx, then Nginx to the app.
