# Chapter 05B: Routed Network Chain

![Chapter 05B routed network chain](diagram.svg)

## Key Concepts

### What Is a Network Chain?

A network chain is a sequence of Layer-3 networks joined by routers.

```text
net_1 -- lab-router-1 -- net_2 -- lab-router-2 -- net_3 -- lab-router-3 -- net_4
```

```text
+--------------------------+    +--------------------------+    +--------------------------+    +--------------------------+
| net_1                    |    | net_2                    |    | net_3                    |    | net_4                    |
| 10.50.1.0/24             |    | 10.50.2.0/24             |    | 10.50.3.0/24             |    | 10.50.4.0/24             |
|                          |    |                          |    |                          |    |                          |
|   +------------------+   |    |   +------------------+   |    |   +------------------+   |    |   +------------------+   |
|   | shell-1          |   |    |   | shell-2          |   |    |   | shell-3          |   |    |   | shell-4          |   |
|   | 10.50.1.10       |   |    |   | 10.50.2.10       |   |    |   | 10.50.3.10       |   |    |   | 10.50.4.10       |   |
|   +------------------+   |    |   +------------------+   |    |   +------------------+   |    |   +------------------+   |
|                          |    |                          |    |                          |    |                          |
|                +--------------------+          +--------------------+          +--------------------+                |
|                | lab-router-1       |          | lab-router-2       |          | lab-router-3       |                |
|                | 10.50.1.2          |          | 10.50.2.3          |          | 10.50.3.3          |                |
+----------------| 10.50.2.2          |----------| 10.50.3.2          |----------| 10.50.4.2          |----------------+
                 +--------------------+          +--------------------+          +--------------------+
```

Each router touches exactly two neighboring networks. A packet may therefore
need multiple routers to reach a remote subnet.

### Connected Routes vs Static Routes

A connected route appears automatically when a node has an interface on that
subnet.

A static route is added manually to tell Linux which next hop to use for a
remote subnet.

### What Is a Hop?

A hop is one Layer-3 forwarding step through a router.

if shell-1 wants to reach shell-3 the packets sent are hop between router till it gets to its destination
```text
shell-1
   |
   v
lab-router-1   <- hop 1
   |
   v
lab-router-2   <- hop 2
   |
   v
shell-3
```

### Forward and Return Paths

A forward path is not enough.

```text
forward:
shell-1 -> lab-router-1 -> lab-router-2 -> shell-3
```

The reply also needs a valid return path:

```text
return:
shell-3 -> lab-router-2 -> lab-router-1 -> shell-1
```

---

## Goal

By the end of this lab you should be able to:

- identify connected routes;
- identify where static routes are required;
- choose the correct next hop;
- build a multi-hop route manually;
- build the return path manually;
- inspect route selection with `ip route get`;
- observe router hops with `traceroute`;
- break one route and diagnose where the path fails;
- automate known-good routes only after understanding them.

---

## Important Lab Rule

The static routes should **not** be preconfigured for the main exercise.

Compose should create:

- four Docker networks;
- four shell containers;
- three router containers;
- router interfaces;
- `NET_ADMIN` and `NET_RAW`;
- `net.ipv4.ip_forward=1` on all routers.

The learner adds the routes manually.

```text
build topology
   ↓
inspect routes
   ↓
predict
   ↓
test failure
   ↓
add one route
   ↓
test again
   ↓
follow the packet
```

---

## Stage Topology

```text
net_1   10.50.1.0/24
net_2   10.50.2.0/24
net_3   10.50.3.0/24
net_4   10.50.4.0/24
```

```text
shell-1   10.50.1.10
shell-2   10.50.2.10
shell-3   10.50.3.10
shell-4   10.50.4.10
```

```text
lab-router-1
  net_1: 10.50.1.2
  net_2: 10.50.2.2

lab-router-2
  net_2: 10.50.2.3
  net_3: 10.50.3.2

lab-router-3
  net_3: 10.50.3.3
  net_4: 10.50.4.2
```

---

# Part 1: Start With Only Connected Routes

## Task 1: Start the Lab

```bash
bash scripts/compose-stage.sh 05b up -d --build
```

Confirm:

```bash
bash scripts/compose-stage.sh 05b ps
```

You should have seven services:

```text
shell-1
shell-2
shell-3
shell-4
lab-router-1
lab-router-2
lab-router-3
```

---

## Task 2: Inspect the Transit Network

We have four different network with `net_1`, `net_2`, `net_3`, `net_4`

```text
a. 3 routers
   lab-router-1, lab-router-2, lab-router-3

b. 4 shells (one inside each subnet)
   shell-1, shell-2, shell-3, shell-4
 
```

Next we break down resources in each network
```text
`net_1` ====> shell_1 and lab-router-1
`net_2` ====> shell_2,  lab-router-1 lab_router-2
`net_3` ====> shell_3, lab-router-2 lab_router-3
`net_4` ====> shell_4,  lab-router-3 
```

Lets inspect `net_1`
```bash
docker network inspect docker-subnet_net_1
```

You should find:

```text
shell-1       10.50.1.10
lab-router-1   10.50.1.2
```

Lets inspect `net_2`
```bash
docker network inspect docker-subnet_net_2
```

You should find:

```text
shell-2        10.50.2.10
lab-router-1   10.50.2.2
lab-router-2   10.50.2.3
```


Lets inspect `net_3`

```bash
docker network inspect docker-subnet_net_3
```

```text
shell-3        10.50.3.10
lab-router-2   10.50.3.2 
lab-router-3   10.50.3.3
```

Lets inspect `net_4`

```bash
docker network inspect docker-subnet_net_4
```

```text
shell-3        10.50.3.10
lab-router-3   10.50.4.2
```

----------

# Part 2: Inspect What Linux Already Knows


## Task 3: Inspect `shell-1`

Check the shell ip-address 
```bash
bash scripts/compose-stage.sh 05b exec shell-1 ip addr
```
You should see
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host proto kernel_lo
       valid_lft forever preferred_lft forever
2: eth0@if255: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether e6:3b:21:b9:69:c3 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.50.1.10/24 brd 10.50.1.255 scope global eth0
       valid_lft forever preferred_lft forever
```text

```text
ip-address
    inet 10.50.1.10/24 brd 10.50.1.255 scope global eth0
```



```bash
bash scripts/compose-stage.sh 05b exec shell-1 ip route
```

The route rules avalaible in the shell
```text
default via 10.50.1.1 dev eth0
10.50.1.0/24 dev eth0 proto kernel scope link src 10.50.1.10
```

subnet ================> 10.50.1.0/24
shell ip address ======>  10.50.1.10
default gateway =======> 10.50.1.1

```text
Note: This shows the shell only know the docker address gate-way inside the network
each network has a gateway address thsi is where packets enter into the network from the
outside every container on a network knows it i address of the gateway on that docker network
```
-------------------------------------------


### Test reachablity
We want to test if shell-1 can reach 

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ip route get 10.50.3.10
```

```text
10.50.3.10 via 10.50.1.1 dev eth0 src 10.50.1.10 uid 0
```
meaning
```text
destination = 10.50.3.10
next hop    = 10.50.1.2
interface   = eth0
source IP   = 10.50.1.10
```
Record the result.

This mean if shell-1 want to send a package to shell-3 
it should sent it to docker gateway 
but docker gateway does not know how to get to shell-3 hence you ping 
shell-3 the package will be transmitted but no response will be recieved

---

Test
```bash
bash scripts/compose-stage.sh 05b exec shell-1 sh

ping -c 3 10.50.3.10
```

You should get package transmitted none recieved

```text
3 packets transmitted, 0 received, 100% packet loss, time 2066ms
```


## Task 4: Inspect `lab-router-1`

Now we will add the route to lab-router-1 to the lab

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1 ip addr
```
```text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host proto kernel_lo
       valid_lft forever preferred_lft forever
2: eth0@if261: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 6a:b1:8c:5e:b7:23 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.50.1.2/24 brd 10.50.1.255 scope global eth0
       valid_lft forever preferred_lft forever
3: eth1@if264: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether ca:4f:d8:79:ab:0c brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.50.2.2/24 brd 10.50.2.255 scope global eth1
       valid_lft forever preferred_lft forever
```

```text
 inet 10.50.2.2/24 brd 10.50.2.255 scope global eth1
```

Next we check the avalble interfaces the lab-router-1 has available
Note: Remeber an interface is like an interaction point where packets can enter or leave our container
a container can have multiple interfaces and also interfaces are how the kernel transmits packets to the
application layer

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1 ip route
```

```text
10.50.1.0/24 dev eth0 proto kernel scope link src 10.50.1.2
10.50.2.0/24 dev eth1 proto kernel scope link src 10.50.2.2
```
You should find connected routes for:

```text
10.50.1.0/24
10.50.2.0/24
```

Notice the lab-router-1 has 3 interfaces and 2 routes rules 

```text
10.50.1.0/24 dev eth0 proto kernel scope link src 10.50.1.2

This shows on network 10.50.1.0/24 (net_1) the lab-router-1 has an ip address of 10.50.1.2

 and 

10.50.2.0/24 dev eth1 proto kernel scope link src 10.50.2.2

This shows on network 10.50.2.0(net_2) the lab-router-1 has an ip address of 10.50.2.2

```

This is because the lab-router-1 is on net_1 and net_2 so it has ip address on both network
now the effect of this now becomes the lab-router is able to transmit packats from one network to another 
as long as it is on both networks

if you remeber when we transmitted a packets it was sent to the docker gateway where is was dropped as
docker gateway doesnt know how to get the packets from net_1 to net_2. 

But lab-router-1 is on both network so it can
as you can see from the diagram below package sent 

```text
+---------------------------+        +---------------------------+
| net_1                     |        | net_2                     |
| 10.50.1.0/24              |        | 10.50.2.0/24              |
|                           |        |                           |
|   +-------------------+   |        |   +-------------------+   |
|   | shell-1           |   |        |   | shell-2           |   |
|   | 10.50.1.10        |   |        |   | 10.50.2.10        |   |
|   +-------------------+   |        |   +-------------------+   |
|                           |        |                           |
| package >  <><>  +-------------------------+ <> <> < package   |
|   sent           | lab-router-1            |         recived   |
|    from shell-1  |                         |                   |
|                  | net_1: 10.50.1.2        |                   |
+------------------| net_2: 10.50.2.2        |--------------------+
                   +-------------------------+
```


---

## Task 5: Inspect `lab-router-2`

```bash
bash scripts/compose-stage.sh 05b exec lab-router-2 ip route
```

You should find connected routes for:

```text
10.50.2.0/24 dev eth0 proto kernel scope link src 10.50.2.3
10.50.3.0/24 dev eth1 proto kernel scope link src 10.50.3.2
```

Notice the lab-router-1 has 3 interfaces and 2 routes rules 

```text
10.50.2.0/24 dev eth0 proto kernel scope link src 10.50.2.3

This shows on network 10.50.1.0/24 (net_2) the lab-router-1 has an ip address of 10.50.1.2

 and 

10.50.3.0/24 dev eth1 proto kernel scope link src 10.50.3.2

This shows on network 10.50.2.0(net_3) the lab-router-1 has an ip address of 10.50.2.2

```


```text
+---------------------------+        +---------------------------+
| net_2                     |        | net_3                     |
| 10.50.1.0/24              |        | 10.50.2.0/24              |
|                           |        |                           |
|   +-------------------+   |        |   +-------------------+   |
|   | shell-2           |   |        |   | shell-3           |   |
|   | 10.50.2.10        |   |        |   | 10.50.3.10        |   |
|   +-------------------+   |        |   +-------------------+   |
|                           |        |                           |
| package >  <><>  +-------------------------+ <> <> < package   |
|   sent           | lab-router-2            |         recived   |
|    from shell-1  |                         |                   |
|                  | net_2: 10.50.2.3        |                   |
+------------------| net_2: 10.50.3.2        |--------------------+
                   +-------------------------+
```

At this point:

```text
shell-1 knows net_1
router-1 knows net_1 and net_2
router-2 knows net_2 and net_3
```

The full path has not been configured yet.

---

# Part 3: Prove the Path Is Broken

## Task 6: Ping Before Adding Routes

First log into the shell-1
```bash
bash scripts/compose-stage.sh 05b exec shell-1 sh
```


Next we try to reach shell-2
```bash
ping -c 2 10.50.2.10
```

```text
--- 10.50.2.10 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss, time 1054ms
```
The failure is expected.

Packets transmitted from shell-1 to shell-2 are being dropped 

Next we investgate why by asking where are the packets sent 
from inside the shell-1 container we will get the route

```bash
ip route get 10.50.2.10
```

```text
10.50.2.10 via 10.50.1.1 dev eth0 src 10.50.1.10 uid 0
    cache
```

What we see when we run the route command is packets are being sent to the default gateway (10.50.1.1)
but the default gateway does not have a way to reach shell2-2 as it is not ont he net_2 network

To close shell
```bash
exit
```

### Question

Where does the failure happen first?

```text
A. shell-3
B. lab-router-2
C. lab-router-1
D. shell-1
```

### Hint

The source host must first know where to send the packet.

---

# Part 4: Teach `shell-1` Its First Next Hop

Now we will add a new route 

## Task 7: Add the Source Route
we have learned that lab-router-1 is reacahable from shell-1 
and also reachable from shell-2 and lastly it can forward packets from shell-1 
to shell-2

`lab-router-1` is directly reachable from `shell-1`.

Add:
This commands add a route to the shell-1 container 



```bash
bash scripts/compose-stage.sh 05b exec shell-1   ip route add 10.50.3.0/24 via 10.50.1.2
```

Confirm:

```bash
bash scripts/compose-stage.sh 05b exec shell-1 ip route
```

Then:

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ip route get 10.50.3.10
```

Expected:

```text
10.50.3.10 via 10.50.1.2 ... src 10.50.1.10
```

### Key Observation

`shell-1` does not need to know the full path.

It only needs its next hop:

```text
net_3 -> 10.50.1.2
```

---

## Task 8: Test Again

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ping -c 2 10.50.3.10
```

It should still fail.

### Question

Why can the packet now leave `shell-1` but still fail?

Inspect:

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1   ip route get 10.50.3.10
```

---

# Part 5: Teach Router 1 the Next Hop

## Task 9: Choose the Correct Next Hop

Which next hop should `lab-router-1` use for `net_3`?

```text
A. 10.50.3.3
B. 10.50.2.3
C. 10.50.2.10
```

Correct answer:

```text
10.50.2.3
```

Add:

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1   ip route add 10.50.3.0/24 via 10.50.2.3
```

Confirm:

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1 ip route
```

---

## Task 10: Confirm IPv4 Forwarding

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1   sysctl net.ipv4.ip_forward

bash scripts/compose-stage.sh 05b exec lab-router-2   sysctl net.ipv4.ip_forward
```

Expected:

```text
net.ipv4.ip_forward = 1
```

Remember:

```text
two interfaces
       !=
packet forwarding enabled
```

---

# Part 6: Follow the Forward Path

The intended path is now:

```text
shell-1
10.50.1.10
     |
     | net_3 via 10.50.1.2
     v
lab-router-1
     |
     | net_3 via 10.50.2.3
     v
lab-router-2
     |
     | net_3 directly connected
     v
shell-3
10.50.3.10
```

Test:

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ping -c 2 10.50.3.10
```

It may still fail.

The request can now reach the destination, but the reply needs its own route.

---

# Part 7: Build the Return Path

## Task 11: Configure `shell-3`

Inspect:

```bash
bash scripts/compose-stage.sh 05b exec shell-3 ip route
```

### Prediction

Which router should `shell-3` use to return traffic to `net_1`?

```text
lab-router-2 = 10.50.3.2
lab-router-3 = 10.50.3.3
```

Add:

```bash
bash scripts/compose-stage.sh 05b exec shell-3   ip route add 10.50.1.0/24 via 10.50.3.2
```

---

## Task 12: Configure `lab-router-2`

Add:

```bash
bash scripts/compose-stage.sh 05b exec lab-router-2   ip route add 10.50.1.0/24 via 10.50.2.2
```

Now the return path is:

```text
shell-3
     |
     | net_1 via 10.50.3.2
     v
lab-router-2
     |
     | net_1 via 10.50.2.2
     v
lab-router-1
     |
     | net_1 directly connected
     v
shell-1
```

---

# Part 8: Prove End-to-End Connectivity

## Task 13: Ping Again

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ping -c 2 10.50.3.10
```

Expected:

```text
2 packets transmitted, 2 packets received, 0% packet loss
```

You have now manually built:

```text
forward path
+
return path
```

---

# Part 9: Observe the Hops

## Task 14: Run `traceroute`

```bash
bash scripts/compose-stage.sh 05b exec shell-1   traceroute -n -m 5 -w 1 10.50.3.10
```

Expected sequence:

```text
1  10.50.1.2
2  10.50.2.3
3  10.50.3.10
```

Meaning:

```text
10.50.1.2   lab-router-1
10.50.2.3   lab-router-2
10.50.3.10  shell-3
```

### Question

Why does `shell-1` only know about `10.50.1.2` even though the packet crosses
two routers?

### Key Lesson

Each node only needs enough information to choose its own next hop.

---

# Part 10: A Host With Two Router Choices

`net_3` contains:

```text
shell-3       10.50.3.10
lab-router-2  10.50.3.2
lab-router-3  10.50.3.3
```

So `shell-3` can use different routers for different destinations.

To the left:

```text
net_1/net_2 -> 10.50.3.2
```

To the right:

```text
net_4 -> 10.50.3.3
```

## Task 15: Add a Route to `net_4`

```bash
bash scripts/compose-stage.sh 05b exec shell-3   ip route add 10.50.4.0/24 via 10.50.3.3
```

Inspect:

```bash
bash scripts/compose-stage.sh 05b exec shell-3 ip route
```

You should now see different next hops for different destination networks.

---

# Part 11: Extend the Chain to `shell-4`

Your target is:

```text
shell-1 -> router-1 -> router-2 -> router-3 -> shell-4
```

Make this succeed:

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ping -c 2 10.50.4.10
```

Determine:

1. the route needed on `shell-1`;
2. the route needed on `lab-router-1`;
3. the route needed on `lab-router-2`;
4. whether `lab-router-3` needs a static route for `net_4`;
5. the return route on `shell-4`;
6. the return routes needed on the routers.

### Rule

At every node ask:

```text
Is the destination directly connected?

If yes:
send directly.

If no:
which directly reachable router is the correct next hop?
```

---

# Part 12: Break It

Once `shell-1 -> shell-3` works, delete the transit route:

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1   ip route delete 10.50.3.0/24 via 10.50.2.3
```

Run:

```bash
bash scripts/compose-stage.sh 05b exec shell-1   traceroute -n -m 5 -w 1 10.50.3.10
```

Observe:

```text
shell-1 still has a valid source route
but the end-to-end path is broken
```

This demonstrates:

```text
valid source route
       !=
complete end-to-end route
```

---

# Part 13: Diagnose Before Fixing

Walk the path:

```bash
bash scripts/compose-stage.sh 05b exec shell-1   ip route get 10.50.3.10

bash scripts/compose-stage.sh 05b exec lab-router-1   ip route get 10.50.3.10

bash scripts/compose-stage.sh 05b exec lab-router-2   ip route get 10.50.3.10
```

Find the first node that cannot make the correct routing decision.

Restore:

```bash
bash scripts/compose-stage.sh 05b exec lab-router-1   ip route add 10.50.3.0/24 via 10.50.2.3
```

Then retest.

---

# Part 14: Automate the Known-Good Routes

Only after the learner has manually built and debugged the chain should the
routes move into startup configuration.

This is where:

```bash
ip route replace ...
```

is useful.

`replace` means:

```text
route missing
    -> add it

route already exists
    -> update it
```

The progression is:

```text
manual configuration
      ↓
understand why it works
      ↓
test
      ↓
break
      ↓
debug
      ↓
automate
```

---

## Key Mental Model

```text
connected route
= Linux already knows the subnet because an interface belongs to it
```

```text
static route
= you tell Linux which next hop to use for a remote network
```

```text
next hop
= the directly reachable router that receives the packet next
```

```text
hop
= one Layer-3 forwarding step
```

```text
source route
      +
each router's next-hop decision
      +
return path
      =
end-to-end connectivity
```

---

## Review Checkpoint

Answer these without looking at your final route tables:

1. Why does `lab-router-1` not need a static route to `net_2`?
2. Why can `shell-1` use `10.50.1.2` as a next hop but not `10.50.2.3`?
3. Why does a valid route on `shell-1` not guarantee connectivity?
4. Why does the reply need a separate return path?
5. What is the difference between a connected route and a static route?
6. Why can `shell-3` choose between two routers?
7. What does `ip route get` show?
8. What does `traceroute` show that `ping` does not?
9. Why does each router only need its next hop rather than the complete path?
10. Why should startup automation come after the manual routing exercise?

---

## Clean Up

```bash
bash scripts/compose-stage.sh 05b down
```
