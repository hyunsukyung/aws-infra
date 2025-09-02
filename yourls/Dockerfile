FROM php:8.2-fpm-alpine

# 원하는 YOURLS 버전 (필요시 변경)
ARG YOURLS_VERSION=1.9.3
ENV YOURLS_VERSION=${YOURLS_VERSION}

# 필수 패키지 + PHP 확장
RUN apk add --no-cache nginx git curl tzdata ca-certificates bash tar gzip \
    && docker-php-ext-install mysqli

# YOURLS 소스 코드: 태그 체크아웃 (tar.gz 대신 git clone → 안정적)
RUN set -eux; \
    rm -rf /var/www/html && mkdir -p /var/www/html; \
    git clone --depth 1 --branch "${YOURLS_VERSION}" \
      https://github.com/YOURLS/YOURLS.git /var/www/html; \
    rm -rf /var/www/html/.git

# 너의 기존 파일들
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
