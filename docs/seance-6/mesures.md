# Mesures séance 6 — team-really-cool

## Valeurs de référence (étape 0)

| Mesure | Valeur |
| --- | --- |
| Heure du relevé ; fenêtre | À renseigner : heure réelle du relevé ; 10 min |
| Révision en service (tag `champion`) | `team-really-cool-scorer-prep-1119180441` (tag à confirmer dans la table du trafic) |
| Latence p95 applicative (`p95 ms` de `measure.py`) | 3,4 ms |
| Latence p95 Cloud Run (`request_latencies`, tableau de bord) | Environ 10 ms sur la capture ; référence à confirmer sur la même fenêtre de 10 min |
| Taux d'erreur (`erreurs`) | 0,0 % |
| Taux d'alerte (`alertes`) | 11,3 % |
| Âge du plus ancien message non acquitté (tableau de bord) | À relever dans le tableau de bord, en secondes |

Dernier relevé fourni : 5 971 livraisons, 5 971 transactions distinctes, score moyen 0,008,
latence p50 1,7 ms et 0,0 % de messages dégradés.

## Critères (étape 1)

Heure à laquelle les critères sont figés : à renseigner au moment de leur adoption, avant le premier déploiement. La bande du taux d’alerte sera fixée et horodatée après l’ombre, avant le passage à 10 %.

Objectif de service cloud proposé : absorber le flux de 10 transactions/s avec une latence p95 Cloud Run ≤ 20 ms, un taux d’erreur applicatif ≤ 1 % et un âge du plus ancien message non acquitté < 60 s. Vérifier également les réponses HTTP 4xx/5xx dans le tableau de bord, car certains échecs de plateforme ne figurent pas dans les logs applicatifs.

Les quatre signaux demandés par le TD sont conservés ci-dessous, avec un contrôle Cloud Run supplémentaire. La latence applicative et la latence Cloud Run ont des périmètres différents : leurs références et leurs seuils sont suivis séparément.

| Signal | Référence | Seuil d'avancement | Seuil de retour arrière | Source |
| --- | --- | --- | --- | --- |
| Latence p95 applicative (TD) | 3,4 ms | ≤ 4 ms | > 5 ms | `measure.py`, `p95 ms` |
| Latence p95 Cloud Run (contrôle supplémentaire) | ≈ 10 ms, à confirmer sur une fenêtre comparable | ≤ 15 ms | > 20 ms | tableau de bord, `request_latencies`, par révision |
| Taux d'erreur | 0,0 % | ≤ 0,5 % | > 1 % | `measure.py`, `erreurs` |
| Taux d'alerte | 11,3 % | À fixer après l'ombre, avant le passage à 10 % | À fixer après l'ombre, avant le passage à 10 % | `measure.py`, `alertes` |
| Âge du plus ancien message | À relever, en secondes | < 30 s | ≥ 60 s | tableau de bord |

Justification des seuils :

- La référence de latence applicative est de 3,4 ms. Les seuils de 4 ms et 5 ms tolèrent respectivement environ 18 % et 47 % de hausse. Ce contrôle répond à la mesure demandée par le TD.
- La référence Cloud Run est approximativement de 10 ms sur la capture. Les budgets proposés de 15 ms pour avancer et 20 ms pour revenir en arrière tolèrent respectivement environ 50 % et 100 % de hausse. Confirmer la référence et figer ces choix avant le déploiement. Ne pas comparer cette métrique aux seuils applicatifs de 4 et 5 ms ; comparer les révisions avec les mêmes fenêtres et réglages d’agrégation.
- Le taux d'erreur observé est nul : les marges sont donc absolues, de 0,5 et 1 point de pourcentage. Elles distinguent quelques échecs isolés d'une dégradation plus forte.
- L'âge du plus ancien message mesure le retard du flux. Nous choisissons moins de 30 s pour avancer et 60 s comme limite de retour arrière, conformément à la grille de repli de l'énoncé. La référence saine reste à vérifier dans le tableau de bord.
- Le taux d'alerte peut changer avec le modèle. Ses bornes seront fixées à partir du taux du candidat et de l'écart candidat/champion mesurés en ombre, en tenant compte du nombre de transactions distinctes au palier à 10 %.

Règle de décision : avancer uniquement si les quatre signaux du TD et le contrôle Cloud Run supplémentaire respectent leurs seuils d'avancement sur la fenêtre d'observation. Revenir en arrière dès qu'un signal franchit son seuil de retour arrière. Entre les deux, prolonger l'observation sans augmenter le trafic.

Borne d'alertes fixée après l'ombre (étape 2) : à renseigner ; écart d'alertes mesuré en ombre : à renseigner en points ; heure : à renseigner avant le passage à 10 %.

Durée d'observation par palier : 5 min après la fin de la commande de changement de trafic ; mesurer sur les 5 dernières minutes pour isoler le palier.

Le dernier relevé correspond à environ 9,95 transactions/s, cohérent avec les 10 messages/s annoncés. Au palier à 10 %, cinq minutes donnent environ 300 transactions au candidat. Contrôler `tx distinctes` avant de juger le taux d’alerte ; si l’échantillon est insuffisant, prolonger jusqu’à six minutes au total, puis maintenir le palier si les données restent insuffisantes.

Pour la latence Cloud Run, noter séparément la fenêtre et les réglages d’agrégation du graphique. Un p95 calculé sur dix minutes ne se déduit pas en faisant la moyenne des p95 affichés point par point.

Commande de retour arrière (étapes 1 à 3) :

```bash
gcloud run services update-traffic team-really-cool-scorer --project advanced-cloud-ai --region europe-west1 --to-tags champion=100
```

Commande de retour arrière (à partir du palier à 100 %) ; `champion=100` si vous avez refusé le challenger :

```bash
gcloud run services update-traffic team-really-cool-scorer --project advanced-cloud-ai --region europe-west1 --to-tags candidate=100
```

## Validation (étape 2)

| Mesure | Valeur |
| --- | --- |
| `contrat.ok` ; latence pour 1 000 lignes (champion, candidat) | ... ; ... ms, ... ms |
| AP globale champion, candidat ; écart et `ic95` | ... , ... ; ... [... ; ...] |
| Segment le plus faible ; son écart et son `ic95` | ... ; ... [... ; ...] |
| Segments non concluants | ... |
| `rejeu` : désaccord, taux d'alerte champion et candidat | ... , ... , ... |
| Révision candidate ; version du modèle | ... ; ... |
| Verdict | ... |

## Mesures par palier

Une ligne par palier, relevée à la fin de la durée d'observation. La révision mesurée est la
nouvelle (`candidate`, puis `next` pour la panne, puis `candidate` au retour) ; la révision de
comparaison est celle qui sert de référence au même moment (`champion` jusqu'au palier à 100 %,
`candidate` pour la panne). Chaque case de signal porte deux valeurs : mesurée / comparaison. Au
palier à 100 % et au retour, la révision de comparaison n'a plus de trafic : comparez à la
référence de l'étape 0.

| Palier | Début | Fin | Révision mesurée | Révision de comparaison | `tx distinctes` (mesurée / comparaison) | p95 ms (mesurée / comparaison) | Erreurs (mesurée / comparaison) | Alertes (mesurée / comparaison) | Âge du plus ancien message | Décision | Critère invoqué |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ombre (0 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 10 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 50 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 100 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| Panne (`next` à 10 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| Retour (`candidate` ou `champion` à 100 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |

En ombre : désaccord ... % et écart d'alertes ... points (`--compare`), sur ... transactions
communes.

Panne : passage à 10 % à ... ; détection à ... ; délai ... min ; signal : ... (valeur ... , borne ...).

Alias `champion` du registre déplacé sur la version ... à ... .

## Réponses aux questions

### Étape 2 — Validation et ombre

1. Écart global, son intervalle, effet de l'avertissement : ...
2. Segments non concluants, et pourquoi ne pas fonder le verdict sur eux : ...
3. Désaccord en ombre comparé au `desaccord` de la validation, deux raisons d'écart : ...
4. Ce que l'ombre apprend que la validation ne pouvait pas apprendre : ...

### Étape 3 — Paliers

1. Transactions distinctes du candidat à 10 %, et si elles suffisent pour juger son taux d'alerte : ...
2. Signal le plus proche du seuil de retour arrière, et à quel palier : ...
3. Effet de `promote.sh` sur le trafic, et rôle de l'alias du registre : ...

### Étape 4 — Panne

1. Premier signal sorti de sa bande ; signaux qui n'ont pas bougé : ...
2. Signal qui aurait suffi seul ; signal qui ne l'aurait jamais vue : ...
3. Transactions traitées par la révision `next` avant la détection ; ce qu'elle en aurait traité à 100 % : ...
