FROM nginx:alpine

RUN apk add --no-cache iproute2 \
    && rm -f /etc/nginx/conf.d/default.conf

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY entrypoint.sh /usr/local/bin/lab-nginx-entrypoint
RUN chmod +x /usr/local/bin/lab-nginx-entrypoint

ENTRYPOINT ["/usr/local/bin/lab-nginx-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
