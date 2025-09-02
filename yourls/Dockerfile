# YOURLS 앱 코드가 포함된 공식 fpm-alpine 이미지 사용
FROM yourls:1.9.3-fpm-alpine

# nginx만 추가해서 php-fpm + nginx 단일 컨테이너 패턴 유지
RUN apk add --no-cache nginx bash tzdata ca-certificates

# 너의 기존 설정/엔트리포인트 그대로
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 8080
CMD ["/bin/sh","-c","/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"]
