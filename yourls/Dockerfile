FROM php:8.2-fpm-alpine

# 원하는 YOURLS 버전(기본 1.9.3). 필요하면 Actions에서 --build-arg로 덮어써도 됨.
ARG YOURLS_VERSION=1.9.3
ENV YOURLS_VERSION=${YOURLS_VERSION}

# 필수 도구 + PHP 확장
RUN apk add --no-cache nginx git curl tzdata ca-certificates bash tar gzip \
    && docker-php-ext-install mysqli

# YOURLS 소스: 태그 자동 판별(1.9.3 또는 v1.9.3) 후 얕은 클론
RUN set -eux; \
    REPO="https://github.com/YOURLS/YOURLS.git"; \
    VER="${YOURLS_VERSION}"; \
    mkdir -p /var/www/html; \
    if git ls-remote --exit-code --tags "$REPO" "refs/tags/${VER}" >/dev/null 2>&1; then \
        REF="${VER}"; \
        echo "Using tag ${REF}"; \
    elif git ls-remote --exit-code --tags "$REPO" "refs/tags/v${VER}" >/dev/null 2>&1; then \
        REF="v${VER}"; \
        echo "Using tag ${REF}"; \
    else \
        echo "ERROR: YOURLS tag not found: '${VER}' or 'v${VER}'"; \
        echo "Available tags (last 20):"; \
        git ls-remote --tags "$REPO" | tail -n 20 || true; \
        exit 1; \
    fi; \
    git clone --depth 1 --branch "${REF}" "$REPO" /var/www/html; \
    rm -rf /var/www/html/.git

# 네가 이미 쓰던 파일들
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
