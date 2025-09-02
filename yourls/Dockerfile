FROM php:8.2-fpm-alpine

ARG YOURLS_VERSION=1.9.3

RUN apk add --no-cache nginx curl tzdata ca-certificates bash tar gzip \
    && docker-php-ext-install mysqli

RUN set -eux; \
    mkdir -p /var/www/html; \
    curl -fL --retry 5 --retry-connrefused --connect-timeout 10 \
      -o /tmp/yourls.tar.gz \
      "https://codeload.github.com/YOURLS/YOURLS/tar.gz/refs/tags/${YOURLS_VERSION}"; \
    tar -xzf /tmp/yourls.tar.gz -C /var/www/html --strip 1; \
    rm -f /tmp/yourls.tar.gz

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
