# ---------- builder: YOURLS 소스만 가져오기 ----------
FROM alpine:3.19 AS builder

ARG YOURLS_VERSION=1.9.2
ENV YOURLS_VERSION=${YOURLS_VERSION}

RUN apk add --no-cache git ca-certificates \
 && git clone --depth 1 --branch "${YOURLS_VERSION}" https://github.com/YOURLS/YOURLS.git /src \
 || (echo "YOURLS tag ${YOURLS_VERSION} not found. Try a valid tag (e.g., 1.9.2)"; exit 1)

# ---------- runtime: php-fpm + nginx 단일 컨테이너 ----------
FROM php:8.2-fpm-alpine

# 필수 패키지 & PHP 확장
RUN apk add --no-cache nginx bash tzdata ca-certificates \
 && docker-php-ext-install mysqli

# 앱 코드 복사
WORKDIR /var/www/html
COPY --from=builder /src /var/www/html

# 너의 설정/엔트리포인트(이미 리포에 있다고 했음)
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

# 권한(필요시 조정)
RUN addgroup -g 82 -S www && adduser -S -D -H -u 82 www-data -G www \
 && chown -R www-data:www /var/www \
 && chmod +x /entrypoint.sh

EXPOSE 8080

# nginx + php-fpm 같이 띄우기
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
