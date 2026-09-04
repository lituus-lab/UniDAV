# Architecture d’UniDAV

UniDAV sépare les règles de données portables des politiques applicatives et réseau. `contentline`
gère la syntaxe commune des RFC 5545/6350 et le pliage sûr en octets. `component` construit un AST
récursif et ordonné qui conserve propriétés inconnues et composants imbriqués. `document` fournit
une validation normative bornée et une normalisation déterministe sans perdre les extensions.
`davxml` encode les requêtes et analyse chaque membre d’une réponse WebDAV
`207 Multi-Status`. `sync` contient une machine d’état déterministe et la politique de reprise.
`sqlite_store` fournit le cache durable optionnel et n’avance le jeton d’une collection que lors
d’un checkpoint explicite. `journal_sync` réclame atomiquement une opération locale éligible,
exécute l’écriture DAV conditionnelle et persiste son résultat.

`client` orchestre le protocole sans posséder les sockets : un `DavTransport` injecté rend
explicites redirections, authentification, politique TLS et injection de pannes. La découverte suit
le chemin endpoint well-known → principal courant → home calendrier/carnet → inventaire Depth-1.

`http_transport` possède deux façades natives minimales : libcurl sur Unix/macOS et WinHTTP sous
Windows. Nim porte la politique commune : HTTPS par défaut, vérifications certificat/nom d’hôte
toujours actives, redirections validées manuellement, aucun downgrade HTTPS, secrets limités à
l’origine, tailles et délais bornés. La façade WinHTTP active aussi la révocation, limite TLS à
1.2/1.3 et emploie proxy et magasins de confiance système. L’exécution native Windows reste une
preuve de livraison ouverte ; les compilations strictes PE32/PE32+ et l’édition de liens PE32+ sont
déjà vérifiées.

## Frontières de sûreté

- Les parseurs limitent octets/lignes et renvoient des erreurs typées.
- Le XML DAV tolère les extensions de namespace inconnues, conformément à WebDAV.
- Les écritures distantes doivent utiliser les préconditions ETag; le transport reste injecté.
- Un sync-token invalide déclenche un inventaire complet, jamais une mutation partielle du cache.
- Les clés étrangères et uniques SQLite empêchent ressources orphelines et doublons.
- Le staging ressource+journal idempotent partage une transaction; ETag reçu et achèvement du
  journal partagent eux aussi une transaction.
- Restaurer une suppression non réclamée est transactionnel : une donnée distante inchangée annule
  le delete, une édition reprend son remplacement et une création non envoyée repart avec
  `If-None-Match: *`.
- Une entrée `running` interrompue n’est récupérée que par un appel explicite au démarrage exclusif,
  afin qu’un second processus actif ne vole pas son travail.
- Le schéma v3 conserve la base commune. Les résultats 412/404 ambigus sont vérifiés par GET; les
  versions base/locale/distante divergentes deviennent des conflits durables. Garder distant ou
  réessayer local met à jour toutes les lignes concernées dans une transaction.
- `If-Match` n’accepte que les entity-tags forts et cités de la RFC 9110. Les validateurs faibles ou
  mal formés sont refusés plutôt que d’émettre une précondition incapable de correspondre fortement.
- Les allocations C/WASM sont libérées uniquement par `unidav_free`/`unidav_wasm_free`.

Voir le [plan de réalisation](ACTION_PLAN.md) et la [spécification](SPECIFICATION.md).
