# Couverture des standards

UniDAV annonce la conformité fonctionnalité par fonctionnalité et corpus par
corpus. Une ligne `Implémenté` désigne un comportement exercé par la suite
locale indiquée. `Partiel` décrit uniquement le sous-ensemble listé et ne
revendique pas la RFC entière. Les Internet-Drafts sont suivis séparément et
ne définissent pas une compatibilité stable.

## Formats et sémantique PIM

| Standard | Périmètre | État | Preuve locale |
|---|---|---|---|
| RFC 6350 | Lignes vCard 4.0, composants, `VERSION` et `FN` obligatoires, cardinalités des propriétés unitaires, valeurs bornées `BDAY`/`ANNIVERSARY`/`DEATHDATE`/`GEO`/`UID` (dates complètes et partielles, heures et offsets), paramètres uniques `PREF`/`PID` et bornés, valeurs `KIND`/`GENDER` et horodatage `REV` UTC | Partiel | `tests/test_formats.nim` |
| RFC 6868 | Échappement par accent circonflexe des paramètres | Implémenté | `tests/test_formats.nim` |
| RFC 5545 | Conteneur iCalendar unique, composants lossless, validation centrale (propriétés obligatoires UID/DTSTAMP, cardinalités et placement des composants et propriétés connues, CALSCALE/METHOD/PRODID, RANGE de RECURRENCE-ID, paramètres VALUE/TZID temporels, durées positives, ATTACH URI/BINARY Base64, alarmes TRIGGER/RELATED avec contexte DTSTART/DTEND/DUE et restrictions d’ACTION, observances VTIMEZONE locales avec RDATE/RRULE annuels, VFREEBUSY/FREEBUSY, dates-heures/offsets, états, plages numériques, cohérence et ordre DTSTART/DTEND/DUE, contraintes DTEND/DURATION), validation structurelle RRULE (FREQ, bornes BY*, BYSETPOS, ordinaux BYDAY, UNTIL/COUNT et dépendances DTSTART), cohérence temporelle RDATE/EXDATE/RECURRENCE-ID et périodes RDATE, expansion UTC bornée SECONDLY/MINUTELY/HOURLY/DAILY/WEEKLY/MONTHLY/YEARLY avec filtres BY* et transitions VTIMEZONE RRULE/RDATE bornées | Partiel | `tests/test_formats.nim`, `tests/test_recurrence.nim`, `tests/test_timezone_registry.nim` |
| RFC 7095 | Structure jCard bornée, groupes, paramètres, valeurs structurées/multiples, temps et extensions `unknown` | Partiel | `tests/test_formats.nim` |
| RFC 7265 | Composants jCal bornés, paramètres, valeurs principales, récurrences/périodes et imbrication | Partiel | `tests/test_formats.nim` |
| RFC 7986 | Propriétés iCalendar | Conservées, sans validation sémantique | `tests/test_formats.nim` |
| RFC 9073 | Extensions de publication d'événements | Conservées, sans validation sémantique | `tests/test_formats.nim` |
| RFC 9074 | Extensions VALARM | Conservées, sans validation sémantique | `tests/test_formats.nim` |
| RFC 9253 | Relations iCalendar | Conservées, sans validation sémantique | `tests/test_formats.nim` |
| RFC 8984 | Projection de base `Event`/`Task` et alias d'entrée pour patch lossless | Partiel | `tests/test_formats.nim` |
| RFC 9553 | Projection de base `Card`/`name.full` et alias d'entrée pour patch lossless | Partiel | `tests/test_formats.nim` |
| RFC 9554 | Extensions vCard pour JSContact | Partiel | `src/UniDAV/projection.nim`, `tests/test_formats.nim` (`PROP-ID`, `SCRIPT`, `SERVICE-TYPE`, `USERNAME`) |
| RFC 9555 | Conversion JSContact/vCard | Partiel | projection Card bornée, propriétés enregistrées (ROLE/FBURL/GEO/TZ/PersonalInfo/ORG-DIRECTORY/SOURCE/BIRTHPLACE/DEATHDATE/DEATHPLACE/X-ABLabel), champs structurels et pont de patch lossless |
| RFC 9982 | JSContact 2.0 | Planifié | — |

L'expansion UTC et VTIMEZONE explicite couvre désormais les fréquences et filtres principaux ;
les observances récurrentes de fuseaux, le scheduling, les disponibilités et le free-busy sont
couverts par les sous-ensembles indiqués dans les tableaux, tandis que leurs sémantiques complètes
restent des portes d'implémentation. Les travaux IETF actifs sur JSCalendar 2.0, la
conversion JSCalendar/iCalendar, JSContact 2.0 et la conversion JSContact/vCard
sont suivis comme travaux en cours.

## Protocoles DAV

| Standard | Périmètre | État | Preuve locale |
|---|---|---|---|
| RFC 4918 | PROPFIND, Multi-Status et opérations conditionnelles | Partiel | `tests/test_dav.nim`, `tests/test_client.nim` |
| RFC 5397 | Découverte du principal courant | Sous-ensemble implémenté | `tests/test_client.nim` |
| RFC 4791 | Découverte CalDAV, filtres de composants (`VEVENT`/`VTODO`/`VJOURNAL`), requêtes temporelles, multiget et free-busy borné | Partiel | `tests/test_dav.nim`, `tests/test_client.nim` |
| RFC 6352 | Découverte CardDAV, filtres de propriétés vCard et `text-match` bornés, requête de collection et multiget | Partiel | `tests/test_dav.nim`, `tests/test_client.nim` |
| RFC 6578 | Synchronisation et récupération après jeton invalide | Sous-ensemble implémenté | `tests/test_client.nim` |
| RFC 6764 | Planification SRV/TXT TLS-first et well-known | Cœur implémenté | `tests/test_client.nim` |
| RFC 6638 | Validation URI des adresses utilisateur, méthode iTIP et soumission vers un schedule outbox avec `Originator`/`Recipient` | Partiel | `tests/test_client.nim` |
| RFC 7809 | Découverte `timezone-service-set`, `calendar-timezone-id` et `timezone-id` dans les requêtes | Partiel | `tests/test_client.nim` |
| RFC 7953 | Validation et découverte de `VAVAILABILITY`/`AVAILABLE`, UID/DTSTAMP requis, récurrences des disponibilités, `BUSYTYPE` et extensions `X-*`, `PRIORITY`, dates-heures UTC ou TZID avec `VTIMEZONE` correspondant, et bornes temporelles | Partiel | `tests/test_client.nim`, `tests/test_formats.nim` |

L'exécution du transport, les requêtes DNS, le stockage durable, les horloges
et les données de fuseaux sont des ports injectables fournis par l'hôte. Le
transport natif impose HTTPS, borne requêtes et réponses, valide les
redirections et limite les identifiants à leur origine ;
`tests/test_http_transport.nim` exerce cette politique partagée.

## Interopérabilité et oracles

La suite TLS paramétrée couvre découverte, collections, CRUD conditionnel,
requêtes, multiget, ETag et nettoyage. Un serveur n'est déclaré testé qu'avec
une preuve d'exécution enregistrée. Les configurations maintenues ciblent
Radicale, SabreDAV, Baïkal et Nextcloud.

Le corpus anonymisé versionné est passé en aller-retour dans des versions
épinglées de vobject et icalendar par `nimble testOracles` ; l'acceptation et
la conservation d'un marqueur inconnu sont vérifiées sans afficher le contenu.
libical, iCal4j, sabre/vobject et CalDAVTester restent des portes
supplémentaires. Aucune implémentation ne prévaut sur les RFC ; chaque
divergence est classée et réduite en fixture locale anonymisée.
