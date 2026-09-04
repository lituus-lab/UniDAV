# UniDAV — spécification produit et technique

## Mission

UniDAV est un moteur public Apache-2.0, écrit en Nim 2.x, pour lire, valider, normaliser,
sérialiser et synchroniser vCard/iCalendar via CardDAV/CalDAV. Il ne contient aucune UI, aucun
secret utilisateur et aucune politique commerciale. Concordia est son consommateur canonique.

## Standards et profils

- WebDAV : RFC 4918; WebDAV Sync : RFC 6578.
- CalDAV : RFC 4791; scheduling RFC 6638 pour la découverte d'outbox et la soumission iTIP,
  avec validation stricte du corps et des adresses.
- CardDAV : RFC 6352.
- iCalendar : RFC 5545, extensions RFC 7986, recurrence RFC 7529 quand applicable.
- vCard : RFC 6350 et paramètres RFC 6868.
- Modèles JSON : JSCalendar RFC 8984 et JSContact RFC 9553 comme formats de bridge.

La conformité est déclarée fonctionnalité par fonctionnalité; aucun label « full RFC » n'est
utilisé sans corpus normatif et tests d'interopérabilité correspondants.

## Architecture

```text
formats (content-line, vCard, iCalendar)
  -> model (Card, Calendar, Event, Todo, recurrence)
  -> dav (XML multistatus, discovery, collections, reports)
  -> sync (plan, ETag/sync-token, retry, conflict)
  -> transports (interface injectée; HTTP natif hors du noyau pur)
  -> bridges (C ABI, Python, WASM) et CLI
```

Le parser conserve les propriétés inconnues et leur ordre. La sérialisation est déterministe,
CRLF, pliage à 75 octets sans couper UTF-8. Les limites de taille, profondeur, nombre de propriétés
et expansion de récurrence sont configurables pour éviter les dénis de service.

La validation vCard applique les cardinalités unitaires connues, les valeurs `KIND`, `GENDER` et `UID` enregistrées, ainsi que le timestamp UTC `REV`. La validation iCalendar applique aussi les contraintes sémantiques sûres du profil courant :
`METHOD` et les états RFC 5545 connus, les bornes de `PRIORITY`, `SEQUENCE`,
`PERCENT-COMPLETE` et `REPEAT`, les cardinalités et placements de composants connus, la cohérence type/ordre de `DTSTART` avec `DTEND` ou `DUE`, la structure des `RRULE` (FREQ, bornes BY*, UNTIL/COUNT et dépendances DTSTART), la cohérence temporelle de `RDATE`, `EXDATE` et `RECURRENCE-ID`, les périodes `RDATE`, les valeurs date/date-heure, durées et offsets, l'exclusion
`DTEND`/`DURATION` ou `DUE`/`DURATION`, les propriétés obligatoires de `UID`/`DTSTAMP`,
`VFREEBUSY` et ses bornes UTC ainsi que ses périodes `FREEBUSY`/`FBTYPE`, `VTIMEZONE` et `VALARM`. Les propriétés et composants inconnus restent préservés ;
cette tranche ne constitue pas encore une validation sémantique intégrale de RFC 5545.

## Synchronisation robuste

Une sync est une machine d'état persistable : `discover -> inventory -> diff -> apply remote ->
apply local -> verify -> checkpoint`. Chaque opération possède un identifiant idempotent. Le
checkpoint n'avance qu'après commit SQLite. Les téléchargements conditionnels utilisent ETag;
les envois utilisent `If-Match`/`If-None-Match`; `sync-token` est privilégié avec repli sur
inventaire `PROPFIND Depth: 1` lorsque le serveur signale explicitement `valid-sync-token`.
Si RFC 6578 est indisponible (`405`/`501`) ou si l'inventaire ne fournit aucun jeton, un REPORT
complet `calendar-query`/`addressbook-query` récupère documents et ETag. Le checkpoint reste vide :
le prochain passage refait donc un inventaire complet au lieu d'inventer une capacité serveur.

La synchronisation descendante compare les ETag de l'inventaire au cache, regroupe les lectures
`calendar-multiget`/`addressbook-multiget` par lots bornés, refuse href dupliqué, inattendu ou omis,
valide chaque corps avant stockage, puis applique upserts, tombstones et nouveau jeton dans un
unique `BEGIN IMMEDIATE`. Une erreur de transport, XML ou contenu laisse cache et checkpoint
inchangés. Un simple HTTP 403 n'est jamais assimilé à un jeton invalide. Un href hors origine,
hors collection, non direct ou ambigu est rejeté. Une page tronquée RFC 6578 expose
`moreAvailable`; son jeton intermédiaire est durable avant la page suivante. Un changement distant
qui croise une opération locale active annule tout le batch avec `LocalChangesPendingError`, sans
écraser le document local-first ni avancer le jeton.

Les réponses `207 Multi-Status` sont évaluées ressource par ressource. `401/403` suspendent le
compte, `409/412` déclenchent la résolution de conflit, `423/429/5xx` passent par un backoff
exponentiel borné avec jitter et `Retry-After`. Une annulation ne laisse jamais un checkpoint
partiellement appliqué.
`CancellationToken` permet à l'hôte d'interrompre coopérativement un pull avant son commit
durable; `SyncCancelledError` est renvoyée et cache comme checkpoint restent inchangés.

La résolution par défaut est non destructive : copie conflictuelle + journal explicable. Les
fusions automatiques ne sont autorisées que sur champs indépendants avec base commune connue.
`mergeThreeWay` réalise cette fusion bornée au niveau des propriétés, conserve les extensions,
retourne les chemins en conflit et laisse les valeurs de base intactes en cas de désaccord.
`resolveConflictMerge` ne met à jour le journal et le cache que si cette fusion ne signale aucun
conflit; sinon il retourne les choix à l'application sans mutation.
Les suppressions sont des tombstones horodatés jusqu'à confirmation serveur.

Le journal SQLite version 3 stocke un identifiant d'opération stable, le snapshot sortant, la base
commune, l'ETag de base, l'état, le nombre d'essais et la prochaine échéance. Un worker réclame la prochaine entrée
sous `BEGIN IMMEDIATE`. Création, remplacement et suppression utilisent respectivement
`If-None-Match: *` ou `If-Match`; les statuts 401/403, 409/412 et 423/429/5xx sont persistés comme
suspension, conflit ou reprise. Les reprises après crash sont déclenchées explicitement par le
propriétaire exclusif du store.

Après un 412 ou une reprise ambiguë, UniDAV relit la ressource. Un contenu normalisé identique avec
ETag fort clôt l'opération sans conflit; un contenu divergent crée un enregistrement persistant
base/local/distant. Une suppression déjà visible en 404 est idempotemment achevée. Les résolutions
« garder distant » et « réessayer local sur l'ETag distant » modifient cache, conflit et journal dans
une transaction. Une suppression distante reste un tombstone et n'est jamais matérialisée comme
une fausse ressource vide.

## Stockage de référence

UniDAV fournit actuellement un backend SQLite de référence. Son schéma versionné contient
`schema_meta`, `accounts`, `collections`, `resources`, `sync_journal` et `conflicts`. SQLite utilise
WAL, foreign keys, busy timeout, transactions immédiates pour apply, et migrations monotones. Les
documents bruts sont conservés pour round-trip et diagnostic. Une abstraction de store et une
indexation structurée `objects`/`properties` restent planifiées. Les secrets passent par le
trousseau OS dans Concordia, jamais dans SQLite en clair.

## Transports natifs

Unix et macOS utilisent le shim libcurl durci ; Windows utilise WinHTTP et les magasins de
certificats du système. HTTPS est imposé par défaut, les vérifications certificat/nom d’hôte ne
peuvent pas être désactivées, les corps et en-têtes sont bornés et chaque redirection est traitée
par la politique Nim commune : nombre limité, aucun downgrade HTTPS et aucun secret transmis à une
autre origine. WinHTTP est limité à TLS 1.2/1.3 et active la révocation des certificats. Il refuse
un chemin de bundle PEM : une CA privée doit être installée dans un magasin Windows approprié.
Le code compile et se lie strictement en PE32/PE32+ ; l’exécution sur un runner Windows réel reste
une preuve de livraison ouverte, et non une fonctionnalité manquante masquée.

Les patches de projection valident le profil de récurrence exposé aux hôtes légers : un `FREQ`
pris en charge, `INTERVAL`/`COUNT` positifs, exclusivité `COUNT`/`UNTIL`, mois et jours bornés,
ordinaux de jours valides, aucune clause dupliquée ou inconnue. Une règle serveur non éditée reste
préservée sans perte ; ce profil n’est pas présenté comme un moteur complet d’évaluation RFC 5545.
Le moteur expose également une expansion UTC bornée pour `SECONDLY`, `MINUTELY`, `HOURLY`,
`DAILY`, `WEEKLY`, `MONTHLY` et `YEARLY`, avec `COUNT`, `UNTIL`, `INTERVAL`, `BYHOUR`,
`BYMINUTE`, `BYSECOND`, `BYMONTH`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`, `WKST`
et les filtres de jours, y compris les ordinaux `BYDAY` mensuels. Les dates locales avec fuseau
échouent explicitement avant tout travail non borné. `expandRecurrenceSet` applique aussi les ajouts
`RDATE` et suppressions `EXDATE`, avec déduplication, tri et même limite de sortie.
`TimezoneRegistry` accepte aussi des définitions `VTIMEZONE` bornées et résout l’offset de la
dernière observance `STANDARD`/`DAYLIGHT`, y compris les transitions `RRULE` et `RDATE` bornées.
Une base de fuseaux système reste hors de ce primitif.

Les façades C, Python et WASM exposent également l’expansion bornée des récurrences, la
résolution d’offsets `VTIMEZONE` explicites et la validation bornée de `calendar-availability`.
Elles exposent aussi le pont JSContact borné (`unidav_to_jscontact` / `unidav_from_jscontact`) et
conservent les membres vCard inconnus via `vCardProps` RFC 9555.

La projection de contact couvre les extensions RFC 9554 ayant un mapping vCard direct : `CREATED`,
`LANGUAGE`, `PRONOUNS`, `GRAMGENDER`, `SOCIALPROFILE`, `LANG`, `IMPP`, `EMAIL`, `TEL`, `NOTE`,
`N`, `ADR`, `ORG`, `NICKNAME`, `MEMBER`, `RELATED`, les médias, clés et adresses de calendrier,
ainsi que leurs paramètres bornés `TYPE`/`PREF`/service et les formes d’objets Card RFC 9555 correspondantes.
Cela reste un pont de projection et de patch lossless; la conversion complète RFC 9555 et JSContact
2.0 (RFC 9982) n’est pas encore revendiquée.

Les requêtes `addressbook-query` peuvent cibler l'existence d'une propriété vCard nommée (par
exemple `EMAIL` ou `TEL`) et appliquer un `text-match` Unicode `contains`; les noms et le texte
sont bornés avant génération XML et `FN` reste le défaut.
Le client CalDAV découvre les propriétés `schedule-inbox-URL`, `schedule-outbox-URL` et
`calendar-user-address-set` lorsqu'elles sont publiées par le principal. `postSchedule` soumet
un iCalendar validé par POST vers l'outbox avec les en-têtes RFC 6638 `Originator` et `Recipient`,
après validation de chaque adresse comme URI absolue sans fragment et du corps avec exactement
une méthode iTIP RFC 5546;
aucune décision d'identité, de participant ou de politique de calendrier n'est prise par le moteur.
`capabilities` lit aussi le champ `DAV` de `OPTIONS` et expose les jetons CalDAV normalisés,
notamment `calendar-schedule`, `calendar-auto-schedule` et `calendar-availability`.
`queryFreeBusy` produit également un REPORT RFC 4791 borné, avec une plage UTC strictement
croissante, sans interpréter localement les disponibilités ni les règles de participation.
Les requêtes `calendar-query` peuvent recevoir la même plage pour filtrer côté serveur les
`VEVENT` (ou explicitement les `VTODO`/`VJOURNAL`); une plage partielle, inversée ou locale est
refusée. Les noms de composants sont bornés avant génération XML.
Les collections CalDAV exposent, lorsqu'ils sont publiés, `calendar-timezone-id` et les URLs du
`timezone-service-set` (RFC 7809); `calendar-query` peut envoyer un `timezone-id` validé.
La propriété `calendar-availability` est conservée puis validée lorsqu'elle contient exactement un
`VAVAILABILITY`, ses `AVAILABLE` conformes, `BUSYTYPE`, `PRIORITY` et, au besoin, des `VTIMEZONE`; le calcul free-busy reste
délégué au serveur.

## ABI et bindings

- C : préfixe figé `unidav_`; handles opaques; `unidav_status`; erreurs récupérables; aucun symbole
  n'élève une exception; `unidav_free` libère toute allocation UniDAV; version ABI indépendante.
- Python : Cython sur la C-ABI, wheels; exceptions typées; buffers copiés ou context-managed.
- WASM : API JSON UTF-8 minimale pour parse/validate/serialize/diff; aucune socket ni secret; le
  navigateur fournit transport et persistance. Build sans threads par défaut.

## Portes qualité

Nim debug/release, corpus RFC positif et négatif, round-trip et fuzz parser, C header drift/test,
pytest, WASM smoke test et sanitizers sur C. L’interop TLS Radicale 3.5.4, SabreDAV 4.6.0, Baïkal
0.10.1 et Nextcloud 33.0.7 est livrée ; les serveurs Apple/Google restent à exercer lorsqu’ils sont
accessibles. Toute correction de
compatibilité ajoute un fixture anonymisé. Une PKI privée utilise un bundle CA explicite sans
désactiver les vérifications TLS.
