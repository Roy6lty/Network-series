#!/bin/sh
set -eu

find_interface() {
  ip -o -4 addr show | awk -v prefix="$1" '$4 ~ ("^" prefix) { print $2; exit }'
}

app_a_if="$(find_interface '10\.10\.11\.')"
app_b_if="$(find_interface '10\.10\.12\.')"
public_if="$(find_interface '10\.10\.30\.')"

test -n "$app_a_if"
test -n "$app_b_if"
test -n "$public_if"

ip route replace default via 10.10.30.1 dev "$public_if"

iptables -F
iptables -t nat -F
iptables -P FORWARD DROP
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$app_a_if" -o "$public_if" -j ACCEPT
iptables -A FORWARD -i "$app_b_if" -o "$public_if" -j ACCEPT
iptables -A FORWARD -i "$public_if" -o "$app_a_if" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$public_if" -o "$app_b_if" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.10.11.0/24 -o "$public_if" -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.10.12.0/24 -o "$public_if" -j MASQUERADE

exec "$@"
