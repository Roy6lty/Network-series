#!/bin/sh
set -eu

sysctl -w net.ipv4.ip_forward=1 >/dev/null

iptables -F
iptables -t nat -F
iptables -P FORWARD DROP

iptables -A FORWARD \
  -m conntrack \
  --ctstate ESTABLISHED,RELATED \
  -j ACCEPT

iptables -A FORWARD \
  -s 10.10.1.0/24 \
  -d 10.10.11.0/24 \
  -p tcp \
  --dport 8000 \
  -j ACCEPT

iptables -A FORWARD \
  -s 10.10.2.0/24 \
  -d 10.10.12.0/24 \
  -p tcp \
  --dport 8000 \
  -j ACCEPT

iptables -A FORWARD \
  -s 10.10.11.0/24 \
  -d 10.10.21.0/24 \
  -p tcp \
  --dport 5432 \
  -j ACCEPT

iptables -A FORWARD \
  -s 10.10.12.0/24 \
  -d 10.10.21.0/24 \
  -p tcp \
  --dport 5432 \
  -j ACCEPT

iptables -A FORWARD \
  -s 10.10.22.0/24 \
  -d 10.10.21.0/24 \
  -p tcp \
  --dport 5432 \
  -j ACCEPT

exec "$@"
