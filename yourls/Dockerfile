FROM php:8.2-fpm-alpine

# 빌드 인자 + 환경변수로 승격(셸에서 확실히 보이게)
ARG YOURLS_VERSION=1.9.3
ENV YOURLS_VERSION=${YOURLS_VERSION}

# 필수 도구 설치 (tar/gzip 포함) + PHP 확장
RUN apk add --no-cache nginx curl tzdata ca-certificates bash tar gzip \
    && docker-php-ext-install mysqli

# YOURLS 다운로드: codeload + 재시도 + 파일로 저장 (파이프 X)
RUN set -eux; \
    mkdir -p /var/www/html; \
    echo "Fetching YOURLS ${YOURLS_VERSION} ..."; \
    curl -fL --retry 5 --retry-connrefused --connect-timeout 10 \
      -o /tmp/yourls.tar.gz \
      "https://codeload.github.com/YOURLS/YOURLS/tar.gz/refs/tags/${YOURLS_VERSION}"; \
    tar -xzf /tmp/yourls.tar.gz -C /var/www/html --strip 1; \
    rm -f /tmp/yourls.tar.gz

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
