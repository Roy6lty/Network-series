FROM alpine:3.20

RUN apk add --no-cache iproute2 iptables tcpdump

COPY entrypoint.sh /usr/local/bin/chain-router-entrypoint
RUN chmod +x /usr/local/bin/chain-router-entrypoint

ENTRYPOINT ["/usr/local/bin/chain-router-entrypoint"]
