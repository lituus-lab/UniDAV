# Nextcloud TLS interoperability fixture

This opt-in fixture was validated with the official `nextcloud:33.0.7-apache` image, SQLite, and
Caddy 2.10.2. It is a disposable compatibility environment, not production guidance.

Create an isolated container network and start Nextcloud with a local-only test account:

```sh
podman network create unidav-interop
podman run --rm --name unidav-nextcloud --network unidav-interop \
  -e SQLITE_DATABASE=nextcloud \
  -e NEXTCLOUD_ADMIN_USER=interop \
  -e NEXTCLOUD_ADMIN_PASSWORD=interop-password \
  -e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
  nextcloud:33.0.7-apache
```

Start Caddy on the same network with the bundled `Caddyfile`, persisting `/data` in a disposable
directory. Then run:

```sh
UNIDAV_INTEROP_URL=https://localhost:8445 \
UNIDAV_INTEROP_USER=interop \
UNIDAV_INTEROP_PASSWORD=interop-password \
UNIDAV_INTEROP_CA_BUNDLE=/path/to/caddy/pki/authorities/local/root.crt \
UNIDAV_INTEROP_CALENDAR=Personal \
UNIDAV_INTEROP_ADDRESSBOOK=Contacts \
nimble testInterop
```

Certificate and hostname verification must remain enabled. The suite removes stale resources with
its fixed test identifiers before execution and cleans them again on exit.

## Fixture d’interopérabilité TLS Nextcloud

Ce fixture opt-in est validé avec l’image officielle `nextcloud:33.0.7-apache`, SQLite et Caddy
2.10.2. Il constitue un environnement de compatibilité jetable, jamais un guide de production.
Lancer Nextcloud et Caddy sur le même réseau isolé, puis utiliser les variables ci-dessus. Les
collections créées par défaut sont `Personal` et `Contacts`. Les vérifications du certificat et du
hostname doivent rester actives ; la suite nettoie ses ressources avant et après le scénario.
