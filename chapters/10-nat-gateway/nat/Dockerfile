FROM alpine:3.20

RUN apk add --no-cache iproute2 iptables

COPY entrypoint.sh /usr/local/bin/nat-entrypoint
RUN chmod +x /usr/local/bin/nat-entrypoint

ENTRYPOINT ["/usr/local/bin/nat-entrypoint"]
