# SQL de la séance 4

Ordre d'exécution, dans BigQuery (`europe-west1`) :

```bash
bq query --use_legacy_sql=false --location europe-west1 < infra/sql/customer_daily.sql
bq query --use_legacy_sql=false --location europe-west1 < infra/sql/terminal_daily.sql
bq query --use_legacy_sql=false --location europe-west1 < infra/sql/check.sql
```

`check.sql` doit renvoyer `client 0` et `terminal 0`. Vérifier ensuite le client de référence :

```sql
SELECT *
FROM `team_really_cool.customer_daily`
WHERE customer_id = '7989449428740969' AND day >= '2026-09-29'
ORDER BY day;
```

Attendu au 2026-10-01 : `n = 5`, `amount_sum = 100.79`.
