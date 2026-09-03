# Baïkal interoperability fixture

This disposable fixture initializes Baïkal `0.10.1` with SQLite, one synthetic user, one
calendar and one address book. `init.php` creates the schema, credentials and collections without
the web installer. Put it in a Baïkal container, run it once, and place the bundled Caddyfile in
front for TLS. The local credentials are `interop` / `interop-password`.

The image used for the validated run was
`docker.io/ckulka/baikal:0.10.1-nginx@sha256:11f1656b3a3e6d69931e483b9a07d605264952da206b53f8b0484fc98f27e177`.

The image's nginx entrypoint is intentionally bypassed by the disposable harness. Start both
services explicitly after running the initializer:

```sh
php /tmp/init.php
/etc/init.d/php8.1-fpm start
nginx -g 'daemon off;'
```

Without PHP-FPM, nginx returns `502 Bad Gateway` for DAV requests even though the container is
running.
