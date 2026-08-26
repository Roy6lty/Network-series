#!/bin/sh
set -eu

: "${LAB_APP_SUBNET:?LAB_APP_SUBNET is required}"
: "${LAB_ROUTER_IP:?LAB_ROUTER_IP is required}"
: "${LAB_UPSTREAM:?LAB_UPSTREAM is required}"

ip route replace "$LAB_APP_SUBNET" via "$LAB_ROUTER_IP"
sed "s/__UPSTREAM__/${LAB_UPSTREAM}/g" \
  /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

exec "$@"
