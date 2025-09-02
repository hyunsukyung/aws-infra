# ---------- builder: YOURLS 소스 ----------
FROM alpine:3.19 AS builder

ARG YOURLS_VERSION=1.9.2
ENV YOURLS_VERSION=${YOURLS_VERSION}

RUN apk add --no-cache git ca-certificates \
 && git clone --depth 1 --branch "${YOURLS_VERSION}" https://github.com/YOURLS/YOURLS.git /src \
 || (echo "YOURLS tag ${YOURLS_VERSION} not found. Try a valid tag (e.g., 1.9.2)"; exit 1)

# ---------- runtime: php-fpm + nginx ----------
FROM php:8.2-fpm-alpine

RUN apk add --no-cache nginx bash tzdata ca-certificates \
 && docker-php-ext-install mysqli

WORKDIR /var/www/html
COPY --from=builder /src /var/www/html

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

# 이미 www-data가 있으므로 생성하지 말고, 권한만 설정
RUN set -eux; \
    chmod +x /entrypoint.sh; \
    chown -R www-data:www-data /var/www/html; \
    chmod -R a+rX /var/www/html

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
