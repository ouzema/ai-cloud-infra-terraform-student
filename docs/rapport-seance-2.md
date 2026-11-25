# Rapport séance 2 — team-really-cool

Service : `team-really-cool-fraud-api`, Cloud Run, `europe-west1`.
Date du relevé : 2026-11-24 23:52 UTC (fenêtre de 10 min).
Image mesurée : `ref-fraud-api:td4`, source `parquet`, révision
`team-really-cool-fraud-api-00006-qqf`.

## Configuration déployée

| Élément | Valeur |
| --- | --- |
| Image | `europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/ref-fraud-api:td4` |
| Révision en service | `team-really-cool-fraud-api-00006-qqf` |
| URL | `https://team-really-cool-fraud-api-ueiaychpgq-ew.a.run.app` |
| Authentification | privée, `roles/run.invoker` pour les identités de `var.invokers` |
| CPU / mémoire | 1 vCPU / 1 GiB |
| Concurrence par instance | 80 |
| Instances | 0 à 3 (`min_instance_count = 0`, `max_instance_count = 3`) |
| Compte d'exécution | `team-really-cool-run@advanced-cloud-ai.iam.gserviceaccount.com` |
| Volume | bucket `advanced-cloud-ai-models`, monté en lecture seule sur `/mnt/models` |
| Variables | `DATA_DIR=/mnt/models/data`, `WEB_CONCURRENCY=1`, `XGB_NTHREAD=1`, `FEATURE_SOURCE=parquet` |

## Mesures demandées

| Mesure | Valeur | Où |
| --- | --- | --- |
| Latence p50, côté client | 25,9 ms | 50 appels `/predict`, mesurés avec `time.perf_counter` |
| Latence p99, côté client | 137,8 ms | idem |
| Latence p50, côté serveur | 18,2 ms | Cloud Monitoring, `request_latencies`, médiane des séries 1 min sur 10 min |
| Latence p99, côté serveur | 158,1 ms | idem |
| Latence de démarrage (cold start) | p50 7,7 s ; p99 8,7 s | Cloud Monitoring, `container/startup_latencies`, sur la révision |
| Instances au pic | 3 (maximum autorisé : 3) | Cloud Monitoring, `container/instance_count`, pendant les essais de charge |
| Nombre d'appels du test | 50 | 10 appels/s pendant 5 s |
| Score de la transaction de référence | 0,00010231 | réponse de `/predict` |

## Protocole

```bash
URL=$(gcloud run services describe team-really-cool-fraud-api \
  --region europe-west1 --format 'value(status.url)')
TOKEN=$(gcloud auth print-identity-token)

# 50 appels authentifiés à /predict, 10 par seconde
# (script httpx : latence client + timings_ms de la réponse)
for i in $(seq 50); do
  curl -s -o /dev/null -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"transactions":[{"TX_ID":"275114cae73280e474ca7ad397c5c429a93121d0","TX_TS":"2026-10-02 00:00:00","CUSTOMER_ID":"7989449428740969","TERMINAL_ID":"93986911","TX_AMOUNT":20.31}]}' \
    "$URL/predict"
  sleep 0.1
done
```

Les timings serveur de la réponse donnent `features` p50 0,60 ms, `predict` p50 0,68 ms et
`handler` p50 1,31 ms. Le reste de la latence client (25,9 ms p50) est le réseau, la sérialisation et
l'attente de la réponse.

## Lecture

- **p50/p99.** Le service répond en quelques dizaines de millisecondes côté client ; le p99 est
  dominé par le premier appel après un démarrage à froid et par la variabilité réseau. Côté serveur,
  le handler reste sous 2 ms : le modèle et les features parquet ne sont pas le goulot.
- **Cold start.** 7,7 s en médiane, 8,7 s au p99 : le conteneur charge le modèle et les deux fichiers
  de compteurs au démarrage. C'est le prix de `min_instance_count = 0`. Pour un SLA serré, garder une
  instance chaude (`min = 1`) ou réduire le temps de chargement.
- **Instances au pic.** Le maximum configuré (3) a été atteint pendant les essais de charge ; le test
  de 50 appels seul reste sur 1 à 2 instances.
- **Dimensionnement.** Avec 1 vCPU et 80 requêtes concurrentes par instance, le service tient le fond
  de 20 req/s et absorbe un pic court ; au-delà, la latence de démarrage et la limite de 3 instances
  deviennent les facteurs dominants.

## Lien du dépôt

Terraform : https://github.com/ouzema/ai-cloud-infra-terraform-student
Service : https://github.com/ouzema/td2-fraud-api-albertschool
