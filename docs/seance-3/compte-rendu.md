# Compte rendu séance 3 — team-really-cool

**Qui a fait quoi.** Yann MEUROU : `infra/pubsub.tf`, abonnement push et file de messages morts, relevés de la file ; Oussema ARIBI : endpoint `POST /pubsub` dans `td2-fraud-api-albertschool` (commit `52af1aa`) et image `team-really-cool-fraud-api:td3` ; Elisa CHEN : mesures Cloud Run, lecture de la lettre morte, réponses 3.1 à 3.3.

**Image déployée.** Pendant la séance 3, le service tournait sur **notre** image
`team-really-cool-fraud-api:td3`, qui contient notre `/pubsub` : il écrit la ligne de log `scored`
(ou `rejected`) puis renvoie 204 (ou 422). La révision citée ci-dessous (`00007-kkh`) est plus
tardive et sert l'image de référence `ref-fraud-api:td4`, déployée pour la séance 4.

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

## Questions

**1.1 — Messages non acquittés et âge du plus ancien pendant les 404.** Les deux courbes montent
sans redescendre : chaque livraison reçoit 404, rien n'est acquitté, Pub/Sub relivre. La file a
atteint 1 749 messages et l'âge du plus ancien 3 662 s (61 min), alors que le flux n'était que de
0,6 msg/s. Ce n'était pas un manque de capacité : dès que `/pubsub` a répondu 204, la file s'est
vidée et l'âge est retombé à 0.

**1.2 — Pourquoi un compte `team-really-cool-push` séparé de `team-really-cool-run` ?** Les deux
comptes ne jouent pas le même rôle. `-push` est l'identité de **l'appelant** : Pub/Sub signe avec
lui le jeton OIDC présenté au service, et il n'a qu'un droit, `roles/run.invoker` sur notre seul
service (`infra/pubsub.tf`). `-run` est l'identité **du service lui-même** : il lit le bucket des
modèles (`roles/storage.objectViewer`) et écrit des logs (`roles/logging.logWriter`), sans droit
d'appel. Séparés, chacun a le minimum : un jeton de livraison volé permet d'appeler le service, pas
de lire les modèles ; une faille dans le service ne donne pas le droit de s'appeler ou d'appeler
d'autres services. Et on peut couper la livraison (retirer `run.invoker` à `-push`) sans toucher au
service.

**1.3 — Que trouve-t-on dans `team-really-cool-tx-dead-pull` après 3 minutes, et pourquoi ?** Des
transactions normales de `ff-tx`, pas des messages invalides. L'endpoint n'existait pas encore :
chaque message a reçu 404 cinq fois (attente de 10 à 60 s entre deux tentatives), donc après
~3 minutes les premiers ont atteint `max_delivery_attempts = 5` et ont été déplacés dans
`team-really-cool-tx-dead`. C'est pour cela que l'étape 3.1 vide d'abord cette file.

**3.1 — À quel débit le retard grossit-il, et qu'est-ce qui l'absorbe ?** Sur ce que nous avons
mesuré, le retard n'a pas grossi par manque de capacité : 20 msg/s passent sans file, avec une
latence `/pubsub` de 28,2 ms p50 côté client et 1,3 ms dans le handler. Avec 80 requêtes
concurrentes par instance et 3 instances au plus (`infra/main.tf`), la capacité théorique est de
240 requêtes en vol, soit ≈ 240 / 0,028 s ≈ 8 500 msg/s si la latence restait à 28 ms : c'est la
**concurrence par instance** qui absorbe un pic, bien avant le nombre maximal d'instances. Nous
n'avons pas suivi le palier à 1 000 msg/s du rejeu de l'enseignant (abonnement créé trop tard) : le
débit exact où le retard commence à grossir n'est pas mesuré. Pour le mesurer, publier des paliers
croissants sur notre topic et relever le palier où `num_undelivered_messages` ne redescend plus.

**3.2 — Sans file de messages morts, que serait devenu le message empoisonné ?** Il aurait reçu 422
à chaque livraison et Pub/Sub l'aurait relivré (backoff 10–60 s) jusqu'à la fin de la rétention de
l'abonnement (`message_retention_duration = 3600s`), puis il aurait été supprimé sans trace. Pendant
une heure, il aurait occupé des livraisons et fait monter l'âge du plus ancien message non acquitté,
ce qui masque un vrai retard. Avec la file, il est écarté après 5 tentatives et reste lisible : nous
y avons lu `42ab0aa3c116f7ecd4538a5f727e879a5aeef181`.

**3.3 — Y a-t-il des doublons de `tx_id`, comment le vérifier, et comment distinguer une nouvelle
livraison d'une seconde publication ?** Pub/Sub livre **au moins une fois** : on acquitte (204)
seulement après le score et le log, donc si le service tombe entre le log et le 204, ou si le 204
arrive après le délai d'acquittement (30 s), le message est relivré et le même `tx_id` est scoré et
loggé deux fois. Pour le vérifier, compter dans les logs `scored` les `tx_id` qui apparaissent plus
d'une fois :

```bash
gcloud logging read 'resource.labels.service_name="team-really-cool-fraud-api" AND jsonPayload.message="scored"' \
  --freshness 1d --format 'value(jsonPayload.tx_id)' | sort | uniq -d | wc -l
```

Résultat (relevé du 25/11, 50 000 lignes `scored` du 16/11 au 25/11, limite de lecture atteinte) :
49 300 `tx_id` distincts ; **un seul** `tx_id` en double, `7c318ce1…`, présent 701 fois, toujours avec
`delivery_attempt` = 1 : c'est la transaction de test republiée par nos essais de charge (seconde
publication), pas une relivraison. 508 lignes ont `delivery_attempt` > 1, mais leurs `tx_id` n'y
figurent qu'une fois : les tentatives précédentes avaient échoué (404 avant `/pubsub`, ou
démarrage à froid) sans écrire de ligne `scored`. Nous n'observons donc aucun doublon dû à une
relivraison sur cette fenêtre. Pour distinguer les deux cas : une **nouvelle livraison** garde le même
`message_id` et a un `delivery_attempt` > 1 ; une **seconde publication** a un `message_id`
différent pour le même `tx_id`, avec `delivery_attempt` = 1. Limite : notre ligne `scored` contient
`tx_id` et `delivery_attempt` mais pas `message_id` (il est dans l'enveloppe, `message.messageId`) ;
il faudrait l'ajouter au log pour séparer les deux cas sans ambiguïté. Le message empoisonné montre le
premier cas : même message, `delivery_attempt` de 1 à 5. Comme le score est déterministe pour un même
`tx_id`, une relivraison ne change pas le résultat, mais elle duplique la ligne : la déduplication
se fait à la lecture, sur `TX_ID` (c'est ce que fait `infra/sql/customer_daily.sql`).

