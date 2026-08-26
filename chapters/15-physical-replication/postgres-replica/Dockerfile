FROM postgres:16

RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 \
    && rm -rf /var/lib/apt/lists/*

COPY lab-entrypoint.sh /usr/local/bin/replica-lab-entrypoint
RUN chmod +x /usr/local/bin/replica-lab-entrypoint

ENTRYPOINT ["/usr/local/bin/replica-lab-entrypoint"]
