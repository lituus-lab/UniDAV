# SabreDAV TLS interoperability fixture

This fixture pins SabreDAV 4.6.0, uses its PDO SQLite CalDAV/CardDAV backends, and places Caddy in
front of it for private-CA TLS and the RFC 6764 well-known endpoints. It is intended for the opt-in
`nimble testInterop` suite, not for production deployment.

Required environment variables are `UNIDAV_INTEROP_URL`, `UNIDAV_INTEROP_USER`,
`UNIDAV_INTEROP_PASSWORD`, and `UNIDAV_INTEROP_CA_BUNDLE`. The prepared service must contain a
calendar named `Interop Calendar` and an address book named `Interop Address Book`; `init.php`
creates both for the bundled fixture. The test uses fixed resource names, removes stale copies at
startup, and removes its resources again on exit.

Servers with different collection names can set `UNIDAV_INTEROP_CALENDAR` and
`UNIDAV_INTEROP_ADDRESSBOOK`; the defaults are the two fixture names above.

The deployment order is:

1. Run `composer install --no-dev --classmap-authoritative` beside these fixture files.
2. Run `php init.php` once with a writable `data` directory.
3. Serve `server.php` on port 8080 in a network shared with Caddy.
4. Run Caddy with the bundled `Caddyfile` and persist its `/data` directory.
5. Export the four variables above, pointing the CA bundle at Caddy's generated `root.crt`, then
   run `nimble testInterop` from the UniDAV root.

The validated build used `docker.io/library/composer:2@sha256:a8e621bdc0f6b9092f69975c56a88793e2d291311afdc6489fc469a9b3d4d70a`.
The fixture suppresses PHP deprecation output so it cannot corrupt DAV response headers under
newer PHP CLI images.

Do not disable peer or hostname verification. The fixture credentials are deliberately local-only:
`admin` / `admin`.

## Fixture d’interopérabilité TLS SabreDAV

Ce fixture épingle SabreDAV 4.6.0, utilise ses backends CalDAV/CardDAV PDO SQLite et place Caddy
devant lui pour TLS avec autorité privée et les points well-known de la RFC 6764. Il sert à la suite
opt-in `nimble testInterop`, jamais à un déploiement de production.

Les variables requises sont `UNIDAV_INTEROP_URL`, `UNIDAV_INTEROP_USER`,
`UNIDAV_INTEROP_PASSWORD` et `UNIDAV_INTEROP_CA_BUNDLE`. Le service préparé doit contenir un
calendrier `Interop Calendar` et un carnet `Interop Address Book`; `init.php` les crée. Le test
supprime ses ressources fixes avant et après le scénario. Il faut conserver les vérifications du
certificat et du hostname actives. Les identifiants `admin` / `admin` sont strictement locaux.
Les noms différents se configurent avec `UNIDAV_INTEROP_CALENDAR` et
`UNIDAV_INTEROP_ADDRESSBOOK`.
