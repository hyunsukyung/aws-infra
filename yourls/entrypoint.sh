#!/bin/sh
set -e

YOURLS_DIR="/var/www/html"
CONF_DIR="${YOURLS_DIR}/user"
CONF_FILE="${CONF_DIR}/config.php"

: "${DB_HOST:?DB_HOST is required}"
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${YOURLS_SITE:?YOURLS_SITE is required (e.g., http://ALB-DNS)}"
: "${YOURLS_USER:?YOURLS_USER is required}"
: "${YOURLS_PASS:?YOURLS_PASS is required}"

mkdir -p "$CONF_DIR"

if [ ! -f "$CONF_FILE" ]; then
  echo "[entrypoint] generating config.php"
  COOKIEKEY=$(head -c 64 /dev/urandom | od -An -vtx1 | tr -d ' \n')

  # ★ 싱글쿼트 heredoc을 쓰면 $ 가 쉘에서 확장되지 않으므로
  #   PHP 변수는 그대로 적고, 쉘 변수(쿠키키)만 나중에 치환합니다.
  cat > "$CONF_FILE" <<'PHP'
<?php
define( 'YOURLS_DB_USER', getenv('DB_USER') );
define( 'YOURLS_DB_PASS', getenv('DB_PASSWORD') );
define( 'YOURLS_DB_NAME', getenv('DB_NAME') );
define( 'YOURLS_DB_HOST', getenv('DB_HOST') );
define( 'YOURLS_DB_PREFIX', 'yourls_' );

define( 'YOURLS_SITE', getenv('YOURLS_SITE') );
define( 'YOURLS_HOURS_OFFSET', 0 );
define( 'YOURLS_LANG', '' );
define( 'YOURLS_UNIQUE_URLS', true );

$yourls_user_passwords = [
  getenv('YOURLS_USER') => getenv('YOURLS_PASS'),
];

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
  $_SERVER['HTTPS'] = 'on';
}

define( 'YOURLS_COOKIEKEY', '__COOKIEKEY_PLACEHOLDER__' );
PHP

$yourls_reserved_URL = array(
  'yourls','api','admin','login','logout','register','install','upgrade',
  'css','js','images','favicon','robots.txt','u','index.php'
);

  # __COOKIEKEY_PLACEHOLDER__ 를 실제 난수로 치환
  sed -i "s/__COOKIEKEY_PLACEHOLDER__/$COOKIEKEY/" "$CONF_FILE"

  chown -R www-data:www-data "$CONF_DIR"
fi

chown -R www-data:www-data "$YOURLS_DIR"
echo "[entrypoint] ready"
