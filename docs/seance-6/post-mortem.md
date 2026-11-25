# Post-mortem séance 6 — team-really-cool

**Résumé en une phrase.** La révision `next-1125145911`, déployée avec `FEATURE_READER=direct`, a lu
les features par une requête BigQuery par transaction : la p95 est passée de 2,3 ms à 648 ms, avec
3 timeouts client ; le retour à `candidate` a restauré la p95 à 2,3 ms.

## 1. Chronologie

| Heure (UTC) | Événement | Source |
| --- | --- | --- |
| ~14:00:50 | `next-1125145911` reçoit le tag `next` et 10 % du trafic (`candidate` 90 %) | commande `update-traffic` |
| 14:01:00 | premier log `next` : `latency_ms` 681,99, `features_ms` 635,29 | Cloud Logging |
| ~14:01:30 | `measure.py` : `next` p50 426,1 ms / p95 648,1 ms contre `candidate` 1,8 / 2,3 ms ; 3 timeouts client | `measure.py` |
| ~14:01:40 | retour arrière : `candidate` à 100 %, tag `next` retiré | commande `update-traffic` |
| 14:01:13 | dernier log `next` (478,01 ms), aucun après le retour | Cloud Logging |
| ~14:03 | `candidate` p95 2,3 ms, 0 % d'erreurs, 0 % de dégradés | `measure.py` |

## 2. Signal

- **Signal qui a détecté la panne :** latence p95 (et `features_ms`). Valeur `next` : 648,1 ms de p95
  (635 ms de features) ; référence `candidate` : 2,3 ms de p95 (1,79 ms de features) ; borne de
  retour arrière : > 20 ms Cloud Run ou > 5 ms applicatif. Trois requêtes client ont expiré avant
  d'atteindre le service (démarrage à froid de la révision `next`).
- **Délai entre le passage à 10 % et la détection :** ≈ 40 s (premier log `next` à 14:01:00, mesure à
  ~14:01:30).
- **Signaux qui n'ont pas bougé :** taux d'erreur applicatif 0 %, dégradés 0 %, score valide (0,005) ;
  le taux d'alerte est resté à 100 % pour les deux révisions parce que le test a réutilisé la même
  transaction. Les 3 timeouts sont côté client/plateforme et n'apparaissent pas dans `measure.py`.
- **Transactions traitées par `next` avant la détection :** 9 livraisons, 1 transaction distincte
  (échantillon de test) ; à 100 %, elle aurait traité les 100 requêtes du test.

## 3. Cause

- **Ce qui a changé entre `candidate` et `next` :** `FEATURE_READER=direct` au lieu de `snapshot`.
  `candidate` lit un instantané précalculé (`snapshot_rows = 895 180`) ; `next` interroge BigQuery à
  chaque transaction.
- **Comment ce changement produit le signal :** la requête BigQuery ajoute ~635 ms par transaction,
  ce qui fait monter la p95 et remplit la file ; le service répond toujours 204 avec un score, donc
  aucune erreur applicative ni aucun message `failed`.
- **Observation qui l'établit :**

```text
2026-11-25T14:01:00.179Z  revision=next-1125145911  latency_ms=681.99  features_ms=635.29
2026-11-25T14:01:13.942Z  revision=next-1125145911  latency_ms=478.01  features_ms=476.97
2026-11-25T14:00:58.510Z  revision=candidate       latency_ms=23.83   features_ms=1.79
```

## 4. Action qui aurait détecté plus tôt

| Action | Ce qu'elle aurait vu | Quand (étape de la livraison) | Délai gagné | Responsable |
| --- | --- | --- | --- | --- |
| Alerte Cloud Run p95 > 50 ms par révision, 60 s | la p95 `next` à 648 ms | pendant le palier à 10 % | ~40 s (détection automatique au lieu de la mesure manuelle) | équipe |
| Comparaison `features_ms` en ombre avant tout trafic | 635 ms contre 1,79 ms | étape 2, avant le déploiement `candidate` | aurait bloqué la livraison avant tout trafic | équipe |
| Test de fumée sur `features_ms` au tag `next` | la régression de lecture des features | étape 4, après `release.sh` | quelques minutes | équipe |

La règle d'alerte a été corrigée dans `infra/release.tf` : elle surveille désormais
`run.googleapis.com/request_latencies` (p95, 50 ms, 60 s), et non `td6_failed`. Une alerte sur les
échecs n'aurait jamais vu cet incident. La commande de l'enseignant
(`release.sh team-really-cool next - FEATURE_READER=direct`) a été rejouée le 25/11 à 14:59 locale
(13:59 UTC) ; elle reproduit exactement la panne.
