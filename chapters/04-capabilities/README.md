# Chapter 04: Linux Capabilities

![Chapter 04 network capability boundary](diagram.svg)

## Goal

By the end of this chapter, you should understand:

* why root inside a container is still restricted;
* what Linux capabilities are;
* the difference between normal file permissions and Linux capabilities;
* why route changes require `CAP_NET_ADMIN`;
* how Docker Compose grants capabilities with `cap_add`;
* why permission to add a route does not mean that the route actually works.

---

## Key Concepts

Docker containers interact with the Linux kernel, but processes inside a container do not automatically receive every privilege available to root on the host.

Linux uses **capabilities** to split traditional root privileges into smaller, more specific permissions.

This allows a process or container to receive only the privileges required for a particular task.

---

## What Are Linux Capabilities?

Traditionally, Linux privilege can be thought of as:

```text
root
or
not root
```

Capabilities divide many traditional root privileges into smaller units.

Examples include:

```text
CAP_NET_ADMIN
CAP_NET_RAW
CAP_SYS_ADMIN
CAP_CHOWN
CAP_KILL
```

Instead of giving a process unrestricted root privileges, Linux can grant only specific privileged operations.

Conceptually:

```text
Traditional root

        all privileged operations
                 |
                 v

Linux capabilities

CAP_NET_ADMIN   -> network administration
CAP_NET_RAW     -> raw network packets and sockets
CAP_CHOWN       -> change file ownership
CAP_KILL        -> send certain signals
CAP_SYS_TIME    -> change system time
...
```

---

# Experiment 1: Build the Test Image

The diagnostic containers use a reusable Alpine-based image containing the tools needed throughout the networking lab.

From the root of the repository, run:

```bash
docker build \
  -t docker-networking-vpc-lab/lab-tools:latest \
  -f chapters/04-capabilities/tools/Dockerfile \
  chapters/04-capabilities/tools
```

The Dockerfile contains tools such as:

```text
iproute2
iptables
tcpdump
curl
netcat
python3
bind-tools
```

This prevents us from repeatedly installing the same diagnostic tools in every chapter.

---

# Experiment 2: Start a Container Without `NET_ADMIN`

For the first experiment, do **not** add `NET_ADMIN`.

Run:

```bash
docker run -d \
  --name lab-tools \
  docker-networking-vpc-lab/lab-tools:latest
```

Enter the container:

```bash
docker exec -it lab-tools sh
```

---

## Predict

Before running the next command:

> Do you think the process inside the container is running as root?

Run:

```bash
id
```

You should see something similar to:

```text
uid=0(root) gid=0(root) groups=0(root)
```

This confirms that the shell is running as root inside the container.

You can also inspect the processes:

```bash
ps
```

Example:

```text
PID   USER     TIME  COMMAND
1     root      0:00 sleep infinity
13    root      0:00 sh
20    root      0:00 ps
```

So the container process is clearly running as:

```text
root
```

But this does **not** mean it has every privilege available to root on the host.

---

# Root Identity vs Privileged Operations

A useful mental model is:

```text
root
=
user identity

Linux capability
=
permission to perform a particular privileged kernel operation
```

Docker removes or limits several capabilities from containers by default.

Therefore:

```text
root inside container
!=
unrestricted root on the host
```

---

# Experiment 3: Normal File Operations

Try:

```bash
cat /etc/os-release
```

This should work.

The command only reads a file that is normally world-readable.

It does not require a special Linux capability.

Conceptually:

```text
cat /etc/os-release
        |
        v
normal file read
        |
        v
ordinary Unix file permissions
```

A normal non-root user can usually read this file as well.

---

## Package Installation Is Different

Now consider:

```bash
apk add curl
```

Installing packages is different from simply reading `/etc/os-release`.

A package manager needs to modify system-owned directories such as:

```text
/usr/bin
/usr/lib
/etc
/lib
/var/lib/apk
```

Therefore package installation normally requires root or equivalent filesystem privileges.

This is mainly about:

```text
filesystem ownership
+
file permissions
```

not a special capability called:

```text
CAP_INSTALL_PACKAGE
```

because no such capability exists.

So:

```text
cat /etc/os-release
        |
        v
ordinary read permission


apk add curl
        |
        v
root normally required to modify system files


ip route add ...
        |
        v
privileged kernel networking operation
        |
        v
CAP_NET_ADMIN required
```

This distinction is important:

```text
Unix file permissions
!=
Linux capabilities
```

---

# Experiment 4: Can Container Root Modify Routing?

First inspect the current routing table:

```bash
ip route
```

You may see something similar to:

```text
default via 172.17.0.1 dev eth0
172.17.0.0/16 dev eth0 scope link src 172.17.0.2
```

Now try adding a route:

```bash
ip route add 10.50.0.0/24 via 172.17.0.1
```

---

## Predict

You are root.

Will the command succeed?

---

## Observe

Without `NET_ADMIN`, Linux should reject the operation:

```text
RTNETLINK answers: Operation not permitted
```

The problem is not the syntax of the route.

The process does not have permission to modify networking state.

We have now demonstrated:

```text
root
 |
 | CAP_NET_ADMIN missing
 v
ip route add ...
 |
 v
Operation not permitted
```

This raises an important question:

> If the process is root, why was it denied?

The answer is Linux capabilities.

---

# Linux Capabilities

Linux splits many traditional root privileges into separate capabilities.

Some important examples are:

1. `CAP_NET_ADMIN`

   Routes, interfaces, firewall rules, NAT and traffic control.

2. `CAP_NET_RAW`

   Raw sockets and packet-level networking operations.

3. `CAP_CHOWN`

   Change file ownership.

4. `CAP_DAC_OVERRIDE`

   Bypass many normal filesystem permission checks.

5. `CAP_SETUID`

   Change process user identity.

6. `CAP_SETGID`

   Change process group identity.

7. `CAP_SYS_PTRACE`

   Debug or trace other processes.

8. `CAP_SYS_TIME`

   Change the system clock.

9. `CAP_SYS_MODULE`

   Load and unload kernel modules.

10. `CAP_SYS_ADMIN`

    Grants a very large collection of administrative operations.

11. `CAP_MKNOD`

    Create special device nodes.

---

# CAP_NET_ADMIN

`CAP_NET_ADMIN` grants permission for many network-administration operations.

Examples include:

* adding and deleting routes;
* changing network interfaces;
* changing interface addresses;
* manipulating firewall rules;
* configuring traffic-control settings;
* modifying certain networking parameters.

Without this capability:

```bash
ip route add 10.10.12.0/24 via 10.10.11.1
```

normally fails with:

```text
RTNETLINK answers: Operation not permitted
```

The kernel understands the command.

It simply refuses permission to perform the operation.

---

# CAP_NET_RAW

`CAP_NET_RAW` allows operations involving raw network sockets and packets.

It is commonly associated with:

```text
ping
raw sockets
packet-generation tools
some packet-level operations
```

Modern Linux systems may sometimes allow `ping` through additional kernel mechanisms, so exact behavior can vary.

For this lab, the important distinction is:

```text
CAP_NET_ADMIN
=
change network configuration

CAP_NET_RAW
=
work with raw network packets and sockets
```

They are separate capabilities because they allow different privileged operations.

---

# Experiment 5: Grant `NET_ADMIN`

Stop and remove the test container:

```bash
docker rm -f lab-tools
```

Start it again with `NET_ADMIN`:

```bash
docker run -d \
  --name lab-tools \
  --cap-add NET_ADMIN \
  docker-networking-vpc-lab/lab-tools:latest
```

Enter the container:

```bash
docker exec -it lab-tools sh
```

Confirm that you are still root:

```bash
id
```

You should still see:

```text
uid=0(root) gid=0(root) groups=0(root)
```

Now run the exact same route command:

```bash
ip route add 10.50.0.0/24 via 172.17.0.1
```

Inspect the routing table:

```bash
ip route
```

You should now see:

```text
10.50.0.0/24 via 172.17.0.1 dev eth0
```

The command succeeded because the process now has:

```text
CAP_NET_ADMIN
```

So:

```text
root
 |
 | CAP_NET_ADMIN present
 v
ip route add ...
 |
 v
kernel accepts route-table modification
```

---

# `cap_add` in Docker Compose

Docker Compose allows capabilities to be added using:

```yaml
cap_add:
  - NET_ADMIN
```

For example:

```yaml
services:
  app-a-test:
    image: docker-networking-vpc-lab/lab-tools:latest
    cap_add:
      - NET_ADMIN
    networks:
      app_a:
        ipv4_address: 10.10.11.10
```

Docker Compose normally uses the capability name without the `CAP_` prefix.

So:

```text
Linux capability      Docker Compose

CAP_NET_ADMIN    ->    NET_ADMIN
CAP_NET_RAW      ->    NET_RAW
CAP_SYS_TIME     ->    SYS_TIME
```

---

# Why Not Use `privileged: true`?

Docker also supports:

```yaml
privileged: true
```

But this gives the container significantly more access than required for this lab.

That would hide the security boundary we are trying to understand.

Instead of:

```yaml
privileged: true
```

we use:

```yaml
cap_add:
  - NET_ADMIN
```

because the container only needs permission to modify networking configuration.

The general rule is:

```text
grant the minimum privilege required
```

---

# Chapter 04 Lab Topology

The network topology does not change.

The six isolated bridge networks from the previous chapter remain:

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
| 10.10.11.10             |      | 10.10.12.10              |
+-------------------------+      +-------------------------+


+-------------------------+      +-------------------------+
| db_a 10.10.21.0/24      |      | db_b 10.10.22.0/24      |
|                         |      |                         |
| db-a-test               |      | db-b-test               |
| 10.10.21.10              |      | 10.10.22.10              |
+-------------------------+      +-------------------------+
```

What changes in this chapter is the **permission boundary**.

---

# Experiment 6: Start the Chapter 04 Lab

Start the stage:

```bash
bash scripts/compose-stage.sh 04 up -d
```

Confirm the containers are running:

```bash
bash scripts/compose-stage.sh 04 ps
```

---

# Confirm the Container User

Run:

```bash
bash scripts/compose-stage.sh 04 exec app-a-test id
```

Expected output:

```text
uid=0(root) gid=0(root) groups=0(root)
```

This confirms that the process runs as root.

The important question is now:

> Which capabilities has Docker given this root process?

---

# Experiment 7: Inspect the Routing Table

Enter `app-a-test`:

```bash
bash scripts/compose-stage.sh 04 exec app-a-test sh
```

Then inspect the routing table:

```bash
ip route
```

You should see the directly connected `app_a` network:

```text
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
```

You will also normally see a default route through Docker's bridge gateway.

---

# Experiment 8: Add a Route

Add:

```bash
ip route add 10.10.12.0/24 via 10.10.11.1
```

Then inspect the routing table again:

```bash
ip route
```

You should now see something similar to:

```text
10.10.11.0/24 dev eth0 scope link src 10.10.11.10
10.10.12.0/24 via 10.10.11.1 dev eth0
```

This proves that the process has permission to modify its routing table.

---

# Prediction Checkpoint

We have successfully added:

```text
10.10.12.0/24 via 10.10.11.1
```

Before testing connectivity, predict what will happen.

Will `app-a-test` now be able to reach:

```text
10.10.12.10
```

Choose one:

```text
A. Yes. A route exists, so communication should work.

B. No. The route exists, but 10.10.11.1 is not acting as the router
   between app_a and app_b.

C. No. Docker does not support routing between networks.
```

Now test:

```bash
ping 10.10.12.10
```

---

# Important Observation

The route:

```text
10.10.12.0/24 via 10.10.11.1
```

does **not** mean communication with `10.10.12.0/24` will work.

It only tells the kernel:

> For packets going to `10.10.12.0/24`, send them to `10.10.11.1` as the next hop.

But:

```text
10.10.11.1
```

is currently the Docker bridge gateway.

It is not our lab router connecting `app_a` to `app_b`.

At this stage we have only demonstrated:

```text
CAP_NET_ADMIN
      |
      v
kernel allows routing-table modification
```

We have **not** created a valid routed path between the two networks.

This distinction is important:

```text
permission to add a route
!=
working route
```

The kernel accepted the routing-table entry.

That does not mean the selected next hop knows how to deliver the packet to the destination network.

---

# Experiment 9: Remove `NET_ADMIN`

Now deliberately break the configuration.

Remove:

```yaml
cap_add:
  - NET_ADMIN
```

from `app-a-test`.

Recreate the container:

```bash
bash scripts/compose-stage.sh 04 up -d
```

Confirm that it is still root:

```bash
bash scripts/compose-stage.sh 04 exec app-a-test id
```

You should still see:

```text
uid=0(root) gid=0(root) groups=0(root)
```

Now attempt:

```bash
bash scripts/compose-stage.sh 04 exec app-a-test \
  ip route add 10.10.12.0/24 via 10.10.11.1
```

Expected result:

```text
RTNETLINK answers: Operation not permitted
```

This demonstrates:

```text
root
 |
 | CAP_NET_ADMIN missing
 v
network modification
 |
 v
denied
```

Restore `NET_ADMIN` afterward.

---

# Key Mental Model

```text
root
=
user identity

Linux capability
=
permission to perform a particular privileged operation
```

For this chapter:

```text
CAP_NET_ADMIN
      |
      +--> modify routes
      +--> modify interfaces
      +--> configure firewall rules
      +--> configure NAT
      +--> configure many network settings
```

Docker Compose:

```yaml
cap_add:
  - NET_ADMIN
```

grants that capability to the container.

But:

```text
CAP_NET_ADMIN
=
permission to configure networking

not

CAP_NET_ADMIN
=
automatic network connectivity
```

A working network connection still requires:

```text
valid interfaces
      +
valid addressing
      +
valid routes
      +
a valid next hop
      +
a forwarding device when crossing subnets
      +
firewall permission
      +
a listening application
```

---

# What We Learned

We started with:

```text
root inside container
```

and discovered that root could perform ordinary filesystem operations but could not modify the routing table.

Then we added:

```text
CAP_NET_ADMIN
```

and repeated the same operation.

The kernel accepted it.

Finally, we learned that:

```text
permission to configure a route
!=
a valid routed network path
```

This prepares us for the next stage, where we introduce an actual router between the isolated Docker networks.

---

## Clean Up

Remove the resources created for this stage:

```bash
bash scripts/compose-stage.sh 04 down
```
