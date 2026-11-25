# Compte rendu séance 4 — team-really-cool

**Qui a fait quoi.** Elisa CHEN : historisation (A), index HNSW (D, partie individuelle) et conclusion ; Oussema ARIBI : requêtes `infra/sql/` et `check.sql` (B) ; Yann MEUROU : mesures des trois sources de features (C).

Dataset : `team_really_cool`, région `europe-west1`. Sources : `fraudfinder.tx_seed` (passé),
`team_really_cool.tx_history` (flux), `fraudfinder.ref_customer_daily` et
`fraudfinder.ref_terminal_daily` (référence).

## A. Historisation

| Mesure | Valeur |
| --- | --- |
| Lignes dans `tx_history` | 301 003 |
| `TX_ID` distincts | 301 003 |
| Doublons (lignes − `TX_ID` distincts) | 0 |
| Octets traités par la requête de comptage, avec filtre sur un jour (`2026-10-03`) | 5,0 Mo |
| Octets traités par la même requête, sans filtre | 12,6 Mo |

Le rejeu de l'enseignant était terminé et l'abonnement `team-really-cool-tx-history` n'avait rien reçu.
Pour débloquer la partie B, le fichier local `data/replay.parquet` (1–3 octobre, 301 003 lignes) a été
chargé directement dans `tx_history` via une table temporaire, puis les cinq colonnes métier ont été
insérées. C'est un contournement documenté : la table n'a donc pas les colonnes `message_id`,
`publish_time` ni `attributes`, et `messages` vaut 0.

**Preuve de l'abonnement (25/11/2026).** Pour ne pas publier sur `ff-replay`, partagé par toutes les
équipes, l'abonnement `team-really-cool-tx-history` a été rattaché à un topic de l'équipe,
`team-really-cool-tx-history-proof` (`infra/history_proof.tf`, `history_topic` dans
`terraform.tfvars`) :

```text
$ terraform apply -target=google_pubsub_topic.history_proof -target=google_pubsub_subscription.tx_history
google_pubsub_subscription.tx_history: Destroying... [id=projects/advanced-cloud-ai/subscriptions/team-really-cool-tx-history]
google_pubsub_topic.history_proof: Creation complete after 3s
google_pubsub_subscription.tx_history: Creation complete after 6s
Apply complete! Resources: 2 added, 0 changed, 1 destroyed.
```

20 transactions de test publiées avec `gcloud pubsub topics publish` (`TX_ID` `td4-proof-01` à
`td4-proof-20`, attribut `source=td4-proof`), sans une ligne de code : Pub/Sub les a écrites seul
dans la table.

```text
SELECT COUNT(*) lignes, COUNT(DISTINCT TX_ID), COUNT(DISTINCT message_id), ANY_VALUE(subscription_name), MIN(publish_time), MAX(publish_time)
FROM team_really_cool.tx_history WHERE subscription_name IS NOT NULL
| lignes | tx_distinctes | messages | abonnement                  | premier             | dernier             |
| 20     | 20            | 20       | team-really-cool-tx-history | 2026-11-25 22:53:49 | 2026-11-25 22:53:56 |

| TX_ID        | TX_AMOUNT | message_id        | publish_time        | attributes             |
| td4-proof-01 | 11.5      | 20361496139896339 | 2026-11-25 22:53:49 | {"source":"td4-proof"} |
| td4-proof-02 | 12.5      | 23484343186886082 | 2026-11-25 22:53:50 | {"source":"td4-proof"} |
```

Table entière après la preuve : 301 023 lignes, 301 023 `TX_ID` distincts, 20 messages. Les
301 003 lignes du contournement restent sans métadonnées ; les chiffres B et C ci-dessous ont été
calculés avant la preuve et ne contiennent pas ces 20 lignes. Limite : 20 messages à faible débit ;
le comportement de l'abonnement sous le palier du rejeu (1 000 msg/s) n'est pas mesuré.

Le filtre sur `2026-10-01` ne découpe rien : toutes les lignes sont postérieures à cette date. Le
filtre d'un jour (`2026-10-03`) montre le prunage de partition : 5,0 Mo au lieu de 12,6 Mo.

Requête de comptage :

```sql
SELECT COUNT(*) AS lignes, COUNT(DISTINCT TX_ID) AS transactions,
       COUNT(DISTINCT message_id) AS messages
FROM `team_really_cool.tx_history`
WHERE TX_TS >= TIMESTAMP '2026-10-01';
```

## B. Agrégats

| Mesure | Valeur |
| --- | --- |
| `check.sql` — client | 0 |
| `check.sql` — terminal | 0 |
| Client `7989449428740969`, jour 2026-10-01 : `n` | 5 |
| Client `7989449428740969`, jour 2026-10-01 : `amount_sum` | 100,79 |

SQL : [`infra/sql/customer_daily.sql`](../../infra/sql/customer_daily.sql),
[`infra/sql/terminal_daily.sql`](../../infra/sql/terminal_daily.sql),
[`infra/sql/check.sql`](../../infra/sql/check.sql).

`customer_daily` contient 903 359 lignes (49 477 clients) du 10 septembre au 3 octobre ;
`terminal_daily` en contient 119 640. La ligne du 1er octobre du client de référence n'existe dans
aucun fichier parquet : elle vient bien du flux.

**B.2 — Où la règle « une transaction du 2 octobre ne lit que les jours jusqu'au 1er » est-elle
appliquée ?** Au moment de la **lecture**, pas dans la table. `customer_daily` contient bien une
ligne pour chaque jour, y compris le jour même (voir l'en-tête de `infra/sql/customer_daily.sql`) ;
c'est le service qui, pour une transaction du jour J, ne somme que les jours `day < J`. Si le
compteur du jour même était lu, la feature contiendrait des transactions **postérieures** à celle
qu'on score (celles de 9 h à 23 h 59 le 2 octobre) : c'est une fuite temporelle. À l'entraînement, le
modèle verrait ainsi une partie du futur et paraîtrait meilleur qu'il ne l'est ; en production, ce
futur n'existe pas encore au moment du paiement, donc la feature n'aurait pas la même distribution
et la performance chuterait. `check.sql` renvoie 0 et 0 : nos compteurs sont identiques à ceux de
référence, sans doublon (déduplication sur `TX_ID` dans `flux`).

**B.3 — `n_fraud` vaut 0 le 1er octobre : erreur ?** Non. Les lignes du flux n'ont pas de label
(`TX_FRAUD` est `NULL`), donc `COUNTIF(TX_FRAUD = 1)` vaut 0. Dans un vrai système, une fraude
n'est connue qu'après la réclamation du client ou l'enquête, souvent plusieurs jours plus tard : le
délai de 7 jours évite de lire un taux de fraude encore incomplet, donc faussement bas.

## C. Trois sources de features

| Source | p50 `features_ms` | p99 `features_ms` | Score de la transaction de référence |
| --- | --- | --- | --- |
| `parquet` | 0,78 ms | 1,5 ms | 0,00010231 |
| `bigquery` | 244,74 ms | 414,23 ms | 0,000192687 |
| `firestore` | 17,74 ms | 128,66 ms | 0,000192687 |

Mesures : 400 messages pour `parquet`, 100 pour `bigquery` et 100 pour `firestore`, à 10–20 msg/s,
`features_ms` lu dans les logs `scored`. Le score de `parquet` diffère parce que ses compteurs
s'arrêtent au 30 septembre ; `bigquery` et `firestore` lisent les compteurs d'octobre et donnent
exactement le même score.

Transaction de référence :

```bash
curl -s -X POST $URL/predict -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"transactions": [{"TX_ID": "275114cae73280e474ca7ad397c5c429a93121d0",
       "TX_TS": "2026-10-02 00:00:00", "CUSTOMER_ID": "7989449428740969",
       "TERMINAL_ID": "93986911", "TX_AMOUNT": 20.31}]}'
```

## D. Justificatifs KYC (extension)

*Partie individuelle — Elisa CHEN.*

Service `team-really-cool-vectors` (Qdrant), 49 394 documents, 384 dimensions. Les deux index ont été
reconstruits et mesurés sur 300 requêtes, 10 voisins.

### `m = 16`

| `ef` | rappel@10 | p50 (ms) | p95 (ms) |
| --- | --- | --- | --- |
| exact | 1,000 | 10,29 | 13,86 |
| 4 | 0,992 | 0,45 | 0,61 |
| 8 | 0,992 | 0,48 | 1,00 |
| 16 | 0,996 | 0,54 | 1,22 |
| 32 | 0,996 | 0,61 | 1,15 |
| 64 | 0,999 | 0,78 | 1,69 |
| 128 | 1,000 | 0,94 | 1,29 |
| 256 | 1,000 | 1,43 | 3,62 |

### `m = 4`

| `ef` | rappel@10 | p50 (ms) | p95 (ms) |
| --- | --- | --- | --- |
| exact | 1,000 | 10,59 | 14,08 |
| 4 | 0,669 | 0,39 | 0,81 |
| 8 | 0,669 | 0,38 | 0,56 |
| 16 | 0,704 | 0,40 | 0,57 |
| 32 | 0,751 | 0,49 | 0,95 |
| 64 | 0,816 | 0,61 | 1,13 |
| 128 | 0,874 | 0,74 | 1,16 |
| 256 | 0,933 | 0,98 | 1,63 |

| Choix | Valeur |
| --- | --- |
| Réglage retenu (`m`, `ef`) | `m` = 16 , `ef` = 4 |
| Rappel@10 au réglage retenu | 0,992 |
| p50 / p95 au réglage retenu | 0,45 ms / 0,61 ms |
| Clients ayant présenté le même document que `0018478647296750` | `3263319564977208`, `2947552228922773`, `0553287702820053` |

`m = 4` plafonne à 0,933 même avec `ef = 256` : il ne tient pas l'objectif de 0,95. `m = 16` avec
`ef = 4` est donc le réglage le moins coûteux qui le tient, avec 0,992 de rappel et 0,45 ms de p50.

Le document 87 est le bulletin de paie de Jules Laurent (Énergie du Sud, 19/09/2026, 59 rue de la
République, Toulouse). Les trois clients qui ont présenté le même document sont
`3263319564977208` (0,9997), `2947552228922773` (0,9996) et `0553287702820053` (0,9990) ; les deux
suivants (0,982/0,980) sont des documents différents (Camille et Noah Laurent).

## Conclusion

Pour scorer en direct, je garderais **Firestore** : il est environ 14× plus rapide que BigQuery par
transaction (p50 17,7 ms contre 244,7 ms) et ses compteurs sont aussi frais que la dernière copie.
`parquet` reste le plus rapide (0,78 ms) mais il est figé au 30 septembre ; il convient comme repli,
pas comme source principale. BigQuery est la bonne source pour recalculer les agrégats, pas pour les
lire à chaque paiement.
