FROM postgres:16

RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 \
    && rm -rf /var/lib/apt/lists/*

COPY pg_hba.conf /etc/postgresql/pg_hba.conf
COPY lab-entrypoint.sh /usr/local/bin/primary-lab-entrypoint
RUN chmod +x /usr/local/bin/primary-lab-entrypoint

ENTRYPOINT ["/usr/local/bin/primary-lab-entrypoint"]
