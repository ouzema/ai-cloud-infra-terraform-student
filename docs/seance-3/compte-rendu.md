# Compte rendu séance 3 — team-really-cool

Configuration : concurrence 80 requêtes par instance, 0 à 3 instances, 1 vCPU / 1 GiB.
Service : `team-really-cool-fraud-api`, image `ref-fraud-api:td4`, révision
`team-really-cool-fraud-api-00007-kkh` (source `parquet`).

| Mesure | Valeur |
| --- | --- |
| Messages traités et débit atteint | 2 522 messages sur la dernière heure ; 100 messages de test à 20 msg/s, plus le flux `ff-tx` à 0,6 msg/s. Palier suivi sans retard : 20 msg/s |
| Nombre maximal de messages en attente, et débit où le retard a commencé à grossir | 1 749 messages ; le retard a grossi pendant la période 404 (0,6 msg/s), pas par manque de capacité. Après le déploiement de `/pubsub`, la file s'est vidée |
| Âge maximal du plus ancien message non acquitté | 3 662 s (61 min) pendant la période 404 ; 0 après déploiement |
| Nombre d'instances au pic | 3 (maximum autorisé : 3) |
| Latence des requêtes (médiane / 99e centile) | client `/pubsub` : 28,2 ms / 36,4 ms ; handler serveur p50 1,3 ms ; Cloud Run p50 5,0 ms / p99 9,9 ms (médiane des séries) |
| `tx_id` lu dans la file de messages morts | `42ab0aa3c116f7ecd4538a5f727e879a5aeef181`, arrivé le 2026-11-18 à 22:15:39, 5 tentatives |
| Lien du dépôt (Terraform et service) | https://github.com/ouzema/ai-cloud-infra-terraform-student — https://github.com/ouzema/td2-fraud-api-albertschool |

## Analyse

- **Limite atteinte.** Ce n'est pas la concurrence par instance ni le nombre maximal d'instances qui
  a bloqué : c'était l'absence de l'endpoint `/pubsub` (404). Pendant cette période, chaque message de
  `ff-tx` était relivré, la file montait à 1 749 messages et l'âge du plus ancien atteignait 61 min.
  Après le déploiement de l'image `td3` puis `td4`, `/pubsub` répond 204, la file se vide et 20 msg/s
  passent avec 1 à 3 instances (concurrence 80, max 3).
- **Sort d'un message rejeté.** Une transaction invalide (`TX_AMOUNT ≤ 0`) reçoit 422 et une ligne
  `rejected` ; Pub/Sub la relivre avec un backoff de 10 à 60 s, puis la met de côté dans
  `team-really-cool-tx-dead` après 5 tentatives. Elle est lisible sans acquittement dans
  `team-really-cool-tx-dead-pull` ; les 10 messages affichés par `metrics.py` en sont la preuve.
  Le test `local-neg` a produit exactement un `rejected` et un 422.
- **Rejeu `ff-replay`.** Le rejeu de l'enseignant était terminé et l'abonnement
  `team-really-cool-tx-history` n'avait rien reçu. Les chiffres de montée en charge ci-dessus
  proviennent donc du flux `ff-tx` (0,6 msg/s) et d'un test direct de 100 messages à 20 msg/s, pas du
  palier à 1 000 msg/s de la séance. La preuve de la panne (404 → file → lettre morte) reste valable.
