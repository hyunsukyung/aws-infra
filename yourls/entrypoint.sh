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

  cat > "$CONF_FILE" <<'PHP'
<?php
// DB
define( 'YOURLS_DB_USER', getenv('DB_USER') );
define( 'YOURLS_DB_PASS', getenv('DB_PASSWORD') );
define( 'YOURLS_DB_NAME', getenv('DB_NAME') );
define( 'YOURLS_DB_HOST', getenv('DB_HOST') );
define( 'YOURLS_DB_PREFIX', 'yourls_' );

// 사이트 URL
define( 'YOURLS_SITE', getenv('YOURLS_SITE') );

// 타임존/언어 등
define( 'YOURLS_HOURS_OFFSET', 0 );
define( 'YOURLS_LANG', '' );
define( 'YOURLS_UNIQUE_URLS', true );

// 사용자/비밀번호 (표준 방식)
\$yourls_user_passwords = [
  getenv('YOURLS_USER') => getenv('YOURLS_PASS'),
];

// HTTPS(프록시 뒤) 처리
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
  \$_SERVER['HTTPS'] = 'on';
}

// 쿠키 키
define( 'YOURLS_COOKIEKEY', getenv('YOURLS_COOKIEKEY') ?: '${COOKIEKEY}' );
PHP

  chown -R www-data:www-data "$CONF_DIR"
fi

chown -R www-data:www-data "$YOURLS_DIR"
echo "[entrypoint] ready"
