# Plan d'action UniDAV

## Phase 0 — contrat et extraction

1. Figer les namespaces, l'ABI `unidav_`, les responsabilités et la matrice RFC.
2. Créer le dépôt depuis UniTemplate sans ses artefacts générés.
3. Copier parser/modèles depuis Concordia avec tests de parité; conserver Concordia comme oracle.

## Phase 1 — formats sûrs

Implémenter content-lines, vCard 3/4, iCalendar, preservation des extensions, validation structurée,
normalisation et sérialisation déterministe. Ajouter limites, corpus, property tests et fuzzing.

## Phase 2 — protocole DAV

Implémenter XML namespaces, `PROPFIND`, discovery principal/home-set, collections, `REPORT`,
`multiget`, `sync-collection`, ETag et requêtes conditionnelles. Transport injecté et serveur de
fixtures déterministe.

## Phase 3 — sync local-first

Journal idempotent, tombstones, checkpoints atomiques, reprise, backoff, annulation, conflits et
observabilité sans données personnelles. Tests de panne à chaque transition.

État au 2026-08-02 : staging et claim atomiques, tombstones, états persistés, backoff, récupération
explicite, écritures ETag conditionnelles, vérification après crash ambigu et choix transactionnels
garder distant/réessayer local sont réalisés. Le pull descendant réalise inventaire initial,
`sync-collection`, repli contrôlé après `valid-sync-token`, multiget borné, validation et commit
atomique du cache et du jeton. Les replis complets `calendar-query`/`addressbook-query`, la
pagination signalée et la protection des opérations locales actives sont réalisés. La primitive
de fusion sûre à trois voies est livrée ; restent son intégration aux workflows, l'annulation
coopérative des pulls est livrée avec conservation atomique du checkpoint ; restent la
télémétrie expurgée et l'intégration applicative complète.
Le job d’interopérabilité TLS couvre Radicale 3.5.4, SabreDAV 4.6.0, Baïkal 0.10.1 et Nextcloud
33.0.7 : découverte, collections, queries, multiget et cycle conditionnel
création/remplacement/suppression. Chaque régression de compatibilité doit devenir un fixture local.

Le transport WinHTTP Windows est implémenté avec la même politique Nim de redirection, origine,
secrets et limites que libcurl. Les compilations strictes PE32/PE32+ et l’édition de liens PE32+
sont validées ; il reste à exécuter la suite commune sur un runner Windows natif.

Complément CalDAV livré : découverte et soumission iTIP RFC 6638 vers l'outbox, requêtes
`free-busy` et `calendar-query` temporelles RFC 4791, références de fuseaux RFC 7809, et validation
de la propriété `calendar-availability`/`VAVAILABILITY` RFC 7953. Ces surfaces restent des
sous-ensembles bornés : le moteur ne calcule pas localement les disponibilités et ne prend aucune
décision d'identité ou de participation.

## Phase 4 — surfaces publiques

CLI `unidav`, C-ABI, binding Python, WASM, documentation exécutable et releases multi-OS signées.

## Phase 5 — Concordia

SQLite et migrations, comptes multiples, keychain, import/export, vues Contacts/Calendrier/Tâches,
centre de synchronisation et réglages. Desktop et web partagent les mêmes tokens et scénarios,
mais utilisent des façades adaptées à leur plateforme.

## Definition of done

Une phase n'est finie que si la doc décrit exactement l'état livré, que les portes applicables
sont vertes — debug/release, C, Python, WASM, couverture et sanitizer —, qu'une preuve
d'interopérabilité existe partout où une affirmation porte sur un serveur, et que le graphe de
dépendances de la famille reste acyclique : c'est `vgraph.cfg` qui le déclare et
`nimble checkVGraph` qui le vérifie.

Les éléments non réalisés restent explicitement listés dans les phases concernées ; aucun rapport
temporaire d'audit n'est conservé dans l'arbre de livraison.
