set -e

YOURLS_DIR="var/www/html"
CONF_DIR="$YOURLS_DIR/user"
CONF_FILE="$CONF_DIR/config.php"

: "${DB_HOST:?DB_HOST is required}"
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${YOURLS_SITE:?YOURLS_SITE is required (e.g., http://ALB-DNS)}"
: "${YOURLS_USER:?YOURLS_USER is required}"
: "${YOURLS_PASS:?YOURLS_PASS is required}"

mkdir -p "$CONF_DIR"

if [ ! -f "$CONF_FILE"]; then
    echo "[entrypoint] generating config.php"
    COOKIEKEY=$(head -c 64 /dev/urandom | od -An -vtx1 | tr -d ' \n')

    cat > "$CONF_FILE" <<PHP
<?php
define( 'YOURLS_DB_USER', '${DB_USER}' );
define( 'YOURLS_DB_PASS', '${DB_PASSWORD}' );
define( 'YOURLS_DB_NAME', '${DB_NAME}' );
define( 'YOURLS_DB_HOST', '${DB_HOST}' );
define( 'YOURLS_DB_PREFIX', 'yourls_' );

define( 'YOURLS_SITE', '${YOURS_SITE}' );
define( 'YOURLS_HOURS_OFFSET', 0 );
define( 'YOURLS_LANG', '' );
define( 'YOURLS_UNIQUE_URLS', true );

define( 'YOURLS_USER', '${YOURLS_USER}' );
define( 'YOURLS_PASS', ${YOURLS_PASS}' );

define( 'YOURLS_COOKIEKEY', '${COOKIEKEY}' );

\$_SERVER['HTTPS'] = isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \&_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https';
PHP
    chown -R www-data:www-data "$CONF_DIR"
fi

chown -R www-data:www-data "$YOURLS_DIR"
echo "[entrypoint] ready"
