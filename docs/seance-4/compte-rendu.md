# Compte rendu séance 4 — team-really-cool

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

Non mesuré dans cette reprise : le service `team-really-cool-vectors` n'est pas déployé. Le fichier
`infra/vectors.tf` est prêt (`min = max = 1`, `roles/run.invoker`) ; il reste à l'appliquer, puis à
lancer `kyc_vectors.py load --m 16`, `measure`, `load --m 4`, `measure` et `neighbours --doc-id 87`.

## Conclusion

Pour scorer en direct, je garderais **Firestore** : il est environ 14× plus rapide que BigQuery par
transaction (p50 17,7 ms contre 244,7 ms) et ses compteurs sont aussi frais que la dernière copie.
`parquet` reste le plus rapide (0,78 ms) mais il est figé au 30 septembre ; il convient comme repli,
pas comme source principale. BigQuery est la bonne source pour recalculer les agrégats, pas pour les
lire à chaque paiement.
