# Post-mortem séance 6 — team-really-cool

**Résumé en une phrase.** La révision `next`, déployée avec `FEATURE_READER=direct`, a lu les
features par une requête BigQuery par transaction : la p95 est passée de 3,1 ms à 564 ms, sans aucune
erreur ; le retour à `candidate` a restauré la p95 à 3,0 ms.

## 1. Chronologie

| Heure (UTC) | Événement | Source |
| --- | --- | --- |
| ~23:59:48 | `next` reçoit le tag `next` et 10 % du trafic (`candidate` 90 %) | commande `update-traffic` |
| 23:59:54 | premier log `next` : `latency_ms` 638,13, `features_ms` 606,15 | Cloud Logging |
| 00:00:20 | `measure.py` : `next` p50 371,6 ms / p95 564,1 ms contre `candidate` 2,0 / 3,1 ms | `measure.py` |
| 00:00:30 | retour arrière : `candidate` à 100 %, tag `next` retiré | commande `update-traffic` |
| 00:00:09 | dernier log `next` (301,73 ms), aucun après le retour | Cloud Logging |
| ~00:02 | `candidate` p95 3,0 ms, 0 % d'erreurs, 0 % de dégradés | `measure.py` |

## 2. Signal

- **Signal qui a détecté la panne :** latence p95 (et `features_ms`). Valeur `next` : 564,1 ms de p95
  (606 ms de features) ; référence `candidate` : 3,1 ms de p95 (1,46 ms de features) ; borne de
  retour arrière : > 20 ms Cloud Run ou > 5 ms applicatif.
- **Délai entre le passage à 10 % et la détection :** ≈ 30 s (premier log `next` à 23:59:54, mesure à
  00:00:20).
- **Signaux qui n'ont pas bougé :** taux d'erreur 0 %, dégradés 0 %, score valide (0,005) ; le taux
  d'alerte est resté à 100 % pour les deux révisions parce que le test a réutilisé la même transaction.
- **Transactions traitées par `next` avant la détection :** 9 livraisons, 1 transaction distincte
  (échantillon de test) ; à 100 %, elle aurait traité les 100 requêtes du test.

## 3. Cause

- **Ce qui a changé entre `candidate` et `next` :** `FEATURE_READER=direct` au lieu de `snapshot`.
  `candidate` lit un instantané précalculé (`snapshot_rows = 895 180`) ; `next` interroge BigQuery à
  chaque transaction.
- **Comment ce changement produit le signal :** la requête BigQuery ajoute ~600 ms par transaction,
  ce qui fait monter la p95 et remplit la file ; le service répond toujours 204 avec un score, donc
  aucune erreur ni aucun message `failed`.
- **Observation qui l'établit :**

```text
2026-11-24T23:59:54.668Z  revision=next       latency_ms=638.13  features_ms=606.15
2026-11-25T00:00:09.971Z  revision=next       latency_ms=301.73  features_ms=301.00
2026-11-25T00:02:xx       revision=candidate  latency_ms=3.0     features_ms=1.46
```

## 4. Action qui aurait détecté plus tôt

| Action | Ce qu'elle aurait vu | Quand (étape de la livraison) | Délai gagné | Responsable |
| --- | --- | --- | --- | --- |
| Alerte Cloud Run p95 > 50 ms par révision, 60 s | la p95 `next` à 564 ms | pendant le palier à 10 % | ~30 s (détection automatique au lieu de la mesure manuelle) | équipe |
| Comparaison `features_ms` en ombre avant tout trafic | 606 ms contre 1,46 ms | étape 2, avant le déploiement `candidate` | aurait bloqué la livraison avant tout trafic | équipe |
| Test de fumée sur `features_ms` au tag `next` | la régression de lecture des features | étape 4, après `release.sh` | quelques minutes | équipe |

La règle d'alerte a été corrigée dans `infra/release.tf` : elle surveille désormais
`run.googleapis.com/request_latencies` (p95, 50 ms, 60 s), et non `td6_failed`. Une alerte sur les
échecs n'aurait jamais vu cet incident.
