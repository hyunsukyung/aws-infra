# 태그 하나: 최신 fpm-alpine (간단/안정)
FROM yourls:fpm-alpine
# 또는 고정 버전이 필요하면:
# FROM yourls:1.9.2-fpm-alpine

RUN apk add --no-cache nginx bash tzdata ca-certificates

# 네 설정 유지
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
