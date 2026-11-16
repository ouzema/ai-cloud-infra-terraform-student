# Compte rendu séance 3 — team-really-cool

Configuration (inchangée pour l'exercice) : concurrence 80 requêtes par instance, 0 à 3 instances, 1 vCPU / 1 Gi.

| Mesure | Valeur |
| --- | --- |
| Messages traités et débit atteint | ... messages ; palier le plus haut suivi sans retard qui grossit : ... messages/s |
| Nombre maximal de messages en attente, et débit où le retard a commencé à grossir | ... messages ; à partir de ... messages/s |
| Âge maximal du plus ancien message non acquitté pendant la montée en charge | ... s, au palier de ... messages/s |
| Nombre d'instances au pic | ... (maximum autorisé : 3) |
| Latence des requêtes (médiane / 99e centile) | ... ms / ... ms |
| `tx_id` lu dans la file de messages morts | ... , arrivé ... min après la publication |
| Lien du dépôt (Terraform et service) | https://github.com/ouzema/ai-cloud-infra-terraform-student — https://github.com/ouzema/td2-fraud-api-albertschool |

## Analyse

- Limite atteinte (concurrence par instance ou nombre maximal d'instances) : ...
- Sort d'un message rejeté : le service répond 422 ; Pub/Sub le relivre (attente de 10 à 60 s), puis le met de côté dans `team-really-cool-tx-dead` après 5 tentatives. Il n'est ni perdu ni relivré indéfiniment.
