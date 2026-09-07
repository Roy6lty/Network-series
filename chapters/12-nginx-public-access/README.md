# Chapter 12: Nginx Public Access

![Chapter 12 Nginx reverse-proxy path](diagram.svg)

## Key Concepts

### A reverse proxy terminates and creates connections

Nginx is an application-layer reverse proxy. It accepts a client connection on
port 80, reads the HTTP request, and creates a new upstream connection to the
application.

```text
public-a-test  -- TCP/HTTP :80 -->  nginx-a
nginx-a        -- TCP/HTTP :8000 --> app-a-test
```

These are two TCP connections, not one connection that the router merely
passes through.

### Nginx is not the router

The router moves IP packets between subnets without understanding HTTP. Nginx
understands HTTP and chooses an upstream from `proxy_pass`, but it still needs
a valid route to reach that upstream.

```text
proxy_pass = which application address Nginx requests
ip route   = which interface and next hop carry that request
iptables   = whether the forwarded packet is allowed
```

### Public access is a policy, not just an address

The public networks are Docker bridge networks. No host port is published by
this Compose overlay. The public test containers reach Nginx over their shared
Docker network, then Nginx reaches the private app subnet through
`lab-router`.

The Chapter 08 firewall permits public A to app A on TCP port 8000 and public B
to app B on TCP port 8000. Therefore a direct public-A request to app A is also
allowed in this lab. It is still a different path from the Nginx proxy path.

## Goal

Add and inspect the two public reverse proxies, then prove the difference
between a client-to-proxy connection and a proxy-to-application connection.

By the end, you should be able to:

- identify the addresses and listeners for `nginx-a` and `nginx-b`;
- read the generated Nginx upstream configuration;
- explain why Nginx needs a route through `lab-router`;
- observe the upstream TCP flow at the router;
- distinguish proxy behavior from router forwarding and firewall policy.

## From Chapter 11

Chapter 11 used Docker DNS and the Chapter 10 NAT path to separate name
resolution from connectivity. The Chapter 12 overlay adds two Nginx services
and changes the two app diagnostics from `sleep infinity` to Python HTTP servers.

The relevant addresses are:

```text
public-a-test  10.10.1.10
nginx-a        10.10.1.3
lab-router     10.10.1.2 on public_a
app-a-test     10.10.11.10:8000

public-b-test  10.10.2.10
nginx-b        10.10.2.3
lab-router     10.10.2.2 on public_b
app-b-test     10.10.12.10:8000
```

`nginx-a` is attached only to `public_a` and receives a route to
`10.10.11.0/24` through `10.10.1.2`. `nginx-b` has the corresponding B-side
configuration.

## What This Stage Adds

The overlay adds:

```text
nginx-a  10.10.1.3  -> app-a-test 10.10.11.10:8000
nginx-b  10.10.2.3  -> app-b-test 10.10.12.10:8000
```

The Nginx entrypoint performs two setup actions before starting Nginx:

1. it installs the app-subnet route through `LAB_ROUTER_IP`;
2. it renders `/etc/nginx/conf.d/default.conf` from the template.

The actual template contains:

```nginx
proxy_pass http://__UPSTREAM__:8000;
```

The entrypoint replaces `__UPSTREAM__` with the address supplied by
`LAB_UPSTREAM` and then runs the image command:

```text
nginx -g "daemon off;"
```

## Progress

- [ ] I can locate both public Nginx services in the cumulative stage.
- [ ] I can identify Nginx's port 80 listener and the app's port 8000 listener.
- [ ] I can explain the route from Nginx to the private app subnet.
- [ ] I can observe the upstream connection at `lab-router`.
- [ ] I can recover after stopping one proxy without changing the app.

## Tasks

### 1. Start the public proxy stage

**Predict:** The six diagnostics, `lab-router`, NAT services, and both Nginx
services should be present. The app containers should now listen on TCP 8000.

**Run:**

```bash
bash scripts/compose-stage.sh 12 up -d --build
bash scripts/compose-stage.sh 12 ps
```

**Observe:** Confirm that `nginx-a`, `nginx-b`, `app-a-test`, `app-b-test`, and
`lab-router` are running. The Compose project has not published Nginx to the
host; tests will run from `public-a-test` and `public-b-test`.

**Explain:** The stage runner combines the earlier network and firewall
overlays with the Chapter 12 service definitions. The public client reaches a
container address, not a host port.

### 2. Inspect listeners, routes, and generated proxy configuration

**Predict:** Each Nginx service should listen on port 80, have a local public
route, and have one specific route to its corresponding private app subnet.

**Run:**

```bash
bash scripts/compose-stage.sh 12 exec nginx-a ss -lnt
bash scripts/compose-stage.sh 12 exec nginx-a ip route
bash scripts/compose-stage.sh 12 exec nginx-a cat /etc/nginx/conf.d/default.conf
bash scripts/compose-stage.sh 12 exec nginx-a nginx -t

bash scripts/compose-stage.sh 12 exec app-a-test ss -lnt
```

**Observe:** The important lines should be similar to:

```text
nginx-a:    0.0.0.0:80
route:      10.10.11.0/24 via 10.10.1.2
proxy_pass: http://10.10.11.10:8000;
app-a-test: 0.0.0.0:8000
```

Interface names and additional default routes may vary. `nginx -t` should
report that the configuration syntax is ok.

**Explain:** Nginx's `proxy_pass` identifies the application endpoint, but the
route installed by `entrypoint.sh` identifies the next hop needed to get there.
`10.10.1.2` is valid because it is `lab-router` on Nginx's own `public_a`
subnet. Nginx does not use the router as an HTTP proxy; it uses it as an IP
next hop for the upstream TCP connection.

### 3. Observe the two legs of a proxied request

**Predict:** The public client can reach `nginx-a:80`. A capture on
`lab-router` should see only the Nginx-to-app leg, because the public client and
Nginx share `public_a` and that first leg does not cross the router.

**Run:** In one terminal, capture the upstream port:

```bash
bash scripts/compose-stage.sh 12 exec lab-router \
  tcpdump -i any -nn 'tcp port 8000'
```

In a second terminal, make the public request:

```bash
bash scripts/compose-stage.sh 12 exec public-a-test \
  curl -sS -D - http://10.10.1.3/
```

Repeat the same exercise for side B if desired:

```bash
bash scripts/compose-stage.sh 12 exec public-b-test \
  curl -sS -D - http://10.10.2.3/
```

Stop the capture with `Ctrl-C`.

**Observe:** The request should return an HTTP response and the capture should
show traffic between `10.10.1.3` and `10.10.11.10` on TCP 8000. The public
client-to-Nginx TCP connection is on `public_a`, while the upstream connection
crosses `lab-router` from `public_a` to `app_a`.

**Explain:** The path is:

```text
public-a-test
    |
    | TCP/HTTP :80
    v
nginx-a 10.10.1.3
    |
    | new TCP/HTTP :8000
    v
lab-router 10.10.1.2 -> 10.10.11.2
    |
    v
app-a-test 10.10.11.10
```

The router forwards packets. Nginx terminates the first HTTP/TCP session and
creates the second one.

### 4. Compare proxy access with direct policy access

**Predict:** A direct request from public A to app A should work because the
Chapter 08 `FORWARD` rule allows public A to app A on TCP 8000. A request from
public A to app B should be blocked because no public-A-to-app-B rule exists.

**Run:**

```bash
bash scripts/compose-stage.sh 12 exec public-a-test \
  curl -sS --connect-timeout 3 http://10.10.11.10:8000/

bash scripts/compose-stage.sh 12 exec public-a-test sh -c \
  'curl -sS --connect-timeout 3 http://10.10.12.10:8000/ || true'

bash scripts/compose-stage.sh 12 exec lab-router \
  iptables -L FORWARD -n -v --line-numbers
```

**Observe:** Direct public-A-to-app-A should return the Python server response.
The public-A-to-app-B request should fail or time out under the default-drop
policy. Rule counters for the permitted TCP 8000 flow should increase after a
request.

**Explain:** Proxy success does not imply that all public-to-app traffic is
allowed. In this lab, the firewall intentionally permits the matching direct
public-A-to-app-A flow as well. Nginx adds an application-layer entry point and
creates a new upstream request; `iptables` still decides whether that upstream
packet may cross the router.

## Expected Observations

```text
public-a-test -> nginx-a:80       = first TCP connection
nginx-a -> app-a-test:8000        = second TCP connection
lab-router                      = forwards the second connection
proxy_pass                      = selects 10.10.11.10:8000
ip route                        = selects 10.10.1.2 as the next hop
iptables FORWARD                = permits or drops the routed packets
```

The two sides are symmetric:

```text
nginx-b 10.10.2.3 -> lab-router 10.10.2.2 -> app-b-test 10.10.12.10:8000
```

An HTTP response proves that both TCP legs and the application request worked.
A packet capture proves packet movement, but not by itself that Nginx or the
Python server accepted the HTTP payload.

## Checkpoint: Definition of Done

You are done when you can answer all of these:

1. What listens on `nginx-a:80`?
2. What listens on `app-a-test:8000`?
3. Why is `10.10.1.2` a valid next hop for `nginx-a`?
4. Which TCP leg appears on the router capture?
5. What does `proxy_pass` select, and what does the route select?
6. Why can a direct public-A-to-app-A request work without being a proxy request?

The progress checklist should be complete, and both public proxy paths should
have returned an HTTP response.

## Break It

Stop only `nginx-a` and compare a proxy failure with a still-healthy app.

**Predict:** The request to `10.10.1.3:80` should fail because no Nginx process
will be listening there. The direct request to `app-a-test:8000` should remain
available under the current Chapter 08 policy.

**Run:**

```bash
bash scripts/compose-stage.sh 12 stop nginx-a

bash scripts/compose-stage.sh 12 exec public-a-test sh -c \
  'curl -sS --connect-timeout 3 http://10.10.1.3/ || true'

bash scripts/compose-stage.sh 12 exec public-a-test \
  curl -sS --connect-timeout 3 http://10.10.11.10:8000/
```

**Observe:** The proxy request should fail, commonly with a connection
refused result. The direct app request should still return the Python server's
response.

**Explain:** Nginx is an application service, not the app process and not the
router. Stopping it removes the port 80 listener but does not stop
`app-a-test`, its route, or the router's forwarding rules.

**Recover:**

```bash
bash scripts/compose-stage.sh 12 up -d --build --force-recreate nginx-a
bash scripts/compose-stage.sh 12 exec public-a-test \
  curl -sS --connect-timeout 3 http://10.10.1.3/
```

## Clean Up

Remove the resources for this cumulative stage:

```bash
bash scripts/compose-stage.sh 12 down
```

## Conclusion: Next Chapter

This stage added public HTTP access without confusing the proxy with the
router. The next chapter adds `postgres-primary` at `10.10.21.20` and follows
an application-to-database path at two boundaries: TCP reachability first, then
PostgreSQL authentication and SQL.
