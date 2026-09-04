# UniDAV

UniDAV est le moteur public Apache-2.0 en Nim de Concordia pour vCard, iCalendar, CardDAV et
CalDAV. Il fournit une CLI, une ABI C stable, un binding Python, une façade WASM, un parseur
WebDAV `207 Multi-Status`, une machine de synchronisation et un cache SQLite optionnel.

Les façades C, Python et WASM exposent validation, normalisation, expansion bornée des récurrences,
résolution d’offsets VTIMEZONE explicites, projection JSON non destructive et
réinjection d’une projection. La projection conserve les noms historiques de Concordia et expose
les alias bornés JSContact `Card`/`name.full` et JSCalendar `Event`/`Task` (`@type`, `version`,
`title`). Le patch ne modifie que les champs exposés par l’hôte dans l’arbre original ; propriétés
inconnues, paramètres, composants imbriqués et valeurs secondaires répétées restent intacts.
L’ABI C expose également `unidav_status()` afin de distinguer une entrée invalide d’une erreur
interne capturée sans analyser un payload de diagnostic.

Sur Unix et macOS, libcurl exécute le transport ; sous Windows, WinHTTP fournit le transport natif.
Les deux exécutent réellement `PROPFIND`, `REPORT`, `PUT`, `DELETE` et les redirections bornées.
TLS et la vérification certificat/hôte sont actifs sans option de
contournement; HTTP en clair doit être explicitement autorisé et ne transporte jamais les secrets
configurés. Une PKI privée peut fournir `HttpTransportConfig.caBundlePath` sans désactiver la
validation. Le bundle explicite s’applique aux hôtes libcurl ; sous Windows, la CA privée doit être
installée dans un magasin de confiance Windows. libcurl 7.85 ou ultérieur est requis sur Unix/macOS.
Le transport WinHTTP compile et se lie en PE32/PE32+ ; son exécution native reste une porte de CI.

```sh
nimble test
nimble testRelease
nimble ctest
nimble coverage
nimble wasmTest
nimble pyTest
nimble testRadicale # opt-in, contre une instance Radicale TLS préparée
nimble testInterop  # opt-in, paramétré pour tout serveur DAV TLS préparé
```

La CLI locale expose `validate`, `normalize`, `project` et `kind` pour les fichiers vCard/iCalendar :

```sh
nim c -r --path:src bin/unidav.nim -- validate contact.vcf
nim c -r --path:src bin/unidav.nim -- normalize contact.vcf
nim c -r --path:src bin/unidav.nim -- project contact.vcf
```

La même suite paramétrée est validée contre Radicale 3.5.4, le fixture SabreDAV 4.6.0 livré dans le
dépôt, Baïkal 0.10.1 et Nextcloud 33.0.7.

Documentation : [spécification française](docs/SPECIFICATION.md),
[English specification](docs/SPECIFICATION.en.md), [plan d’action français](docs/ACTION_PLAN.md),
[English action plan](docs/ACTION_PLAN.en.md).

La conformité est suivie fonctionnalité par fonctionnalité; la documentation ne prétend jamais
qu’une RFC entière est implémentée sans corpus et tests d’interopérabilité correspondants.
