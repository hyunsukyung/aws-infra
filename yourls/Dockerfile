FROM php:8.2-fpm-alpine

RUN apk add --no-cache nginx curl tar tzdata

RUN docker-php-ext-install mysqli && docker-php-ext-enable mysqli


WORKDIR /var/www/html

RUN curl -fsSL https://github.com/YOURLS/YOURLS/archive/refs/tags/1.9.3.tar.gz \
| tar -xz --strip 1 -C /var/www/html

COPY nginx.conf /ect/nginx/conf.d/default.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /run/nginx

EXPOSE 8080
CMD [ "/bin/sh", "-c", "/entrypoint.sh && php-fpm -D && nginx -g 'daemon off;'"  ]