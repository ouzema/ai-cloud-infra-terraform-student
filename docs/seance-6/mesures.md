# Mesures séance 6 — team-really-cool

## Valeurs de référence (étape 0)

| Mesure | Valeur |
| --- | --- |
| Heure du relevé ; fenêtre | 2026-11-19, fenêtre de 10 min (relevé de séance) |
| Révision en service (tag `champion`) | `team-really-cool-scorer-prep-1119180441` (à confirmer dans la table du trafic) |
| Latence p95 applicative (`p95 ms` de `measure.py`) | 3,4 ms |
| Latence p95 Cloud Run (`request_latencies`, tableau de bord) | ≈ 10 ms sur la capture ; à confirmer sur une fenêtre de 10 min |
| Taux d'erreur (`erreurs`) | 0,0 % |
| Taux d'alerte (`alertes`) | 11,3 % |
| Âge du plus ancien message non acquitté (tableau de bord) | non relevé sur la capture ; à lire dans le tableau de bord |

Dernier relevé fourni : 5 971 livraisons, 5 971 transactions distinctes, score moyen 0,008,
latence p50 1,7 ms et 0,0 % de messages dégradés.

## Critères (étape 1)

Heure à laquelle les critères sont figés : **2026-11-19 à 17:30 UTC**. Horodatage reconstitué à
partir des révisions : la révision de base `team-really-cool-scorer-prep-1119180441` a été créée à
18:04 UTC, donc avant le premier déploiement `candidate`. À ajuster si le journal de séance donne une
heure exacte.

Objectif de service cloud proposé : absorber le flux de 10 transactions/s avec une latence p95 Cloud
Run ≤ 20 ms, un taux d'erreur applicatif ≤ 1 % et un âge du plus ancien message non acquitté < 60 s.
Vérifier également les réponses HTTP 4xx/5xx dans le tableau de bord, car certains échecs de
plateforme ne figurent pas dans les logs applicatifs.

Les quatre signaux demandés par le TD sont conservés ci-dessous, avec un contrôle Cloud Run
supplémentaire. La latence applicative et la latence Cloud Run ont des périmètres différents : leurs
références et leurs seuils sont suivis séparément.

| Signal | Référence | Seuil d'avancement | Seuil de retour arrière | Source |
| --- | --- | --- | --- | --- |
| Latence p95 applicative (TD) | 3,4 ms | ≤ 4 ms | > 5 ms | `measure.py`, `p95 ms` |
| Latence p95 Cloud Run (contrôle supplémentaire) | ≈ 10 ms, à confirmer sur une fenêtre comparable | ≤ 15 ms | > 20 ms | tableau de bord, `request_latencies`, par révision |
| Taux d'erreur | 0,0 % | ≤ 0,5 % | > 1 % | `measure.py`, `erreurs` |
| Taux d'alerte | 11,3 % | entre 5,7 % et 17,0 % (grille de repli) | < 5,7 % ou > 17,0 % | `measure.py`, `alertes` |
| Âge du plus ancien message | à relever, en secondes | < 30 s | ≥ 60 s | tableau de bord |

Justification des seuils :

- La référence de latence applicative est de 3,4 ms. Les seuils de 4 ms et 5 ms tolèrent
  respectivement environ 18 % et 47 % de hausse. Ce contrôle répond à la mesure demandée par le TD.
- La référence Cloud Run est approximativement de 10 ms sur la capture. Les budgets proposés de 15 ms
  pour avancer et 20 ms pour revenir en arrière tolèrent respectivement environ 50 % et 100 % de
  hausse. Confirmer la référence et figer ces choix avant le déploiement. Ne pas comparer cette
  métrique aux seuils applicatifs de 4 et 5 ms ; comparer les révisions avec les mêmes fenêtres et
  réglages d'agrégation.
- Le taux d'erreur observé est nul : les marges sont donc absolues, de 0,5 et 1 point de pourcentage.
  Elles distinguent quelques échecs isolés d'une dégradation plus forte.
- L'âge du plus ancien message mesure le retard du flux. Nous choisissons moins de 30 s pour avancer
  et 60 s comme limite de retour arrière, conformément à la grille de repli de l'énoncé. La référence
  saine reste à vérifier dans le tableau de bord.
- Le taux d'alerte peut changer avec le modèle. La borne retenue est celle de la grille de repli
  (0,5× à 1,5× la référence), soit 5,7 % à 17,0 %. La validation de la séance 5 donne 13,43 % pour le
  candidat contre 13,83 % pour le champion, soit un écart de −0,4 point : un écart de cet ordre n'est
  pas un motif de retour arrière. La borne sera confirmée après l'ombre.

Règle de décision : avancer uniquement si les quatre signaux du TD et le contrôle Cloud Run
supplémentaire respectent leurs seuils d'avancement sur la fenêtre d'observation. Revenir en arrière
dès qu'un signal franchit son seuil de retour arrière. Entre les deux, prolonger l'observation sans
augmenter le trafic.

Borne d'alertes fixée après l'ombre (étape 2) : l'ombre n'a pas été exécutée dans cette reprise ;
borne de repli retenue : 5,7 % à 17,0 % ; heure : 17:30 UTC. Écart d'alertes mesuré en validation :
−0,4 point (13,43 % contre 13,83 %).

L'alerte appliquée dans `infra/release.tf` surveille la p95 Cloud Run > 50 ms pendant 60 s, par
révision. Le seuil est au-dessus du seuil de retour arrière (20 ms) pour absorber un cold start isolé ;
il déclenche sur la régression de `next` (648 ms), que l'ancienne alerte sur `td6_failed` n'aurait pas
vue.

Durée d'observation par palier : 5 min après la fin de la commande de changement de trafic ; mesurer
sur les 5 dernières minutes pour isoler le palier. Six minutes au maximum pour que les trois paliers
tiennent dans les 25 minutes de l'étape 3.

Le dernier relevé correspond à environ 9,95 transactions/s, cohérent avec les 10 messages/s annoncés.
Au palier à 10 %, cinq minutes donnent environ 300 transactions au candidat. Contrôler `tx distinctes`
avant de juger le taux d'alerte ; si l'échantillon est insuffisant, prolonger jusqu'à six minutes au
total, puis maintenir le palier si les données restent insuffisantes.

Pour la latence Cloud Run, noter séparément la fenêtre et les réglages d'agrégation du graphique. Un
p95 calculé sur dix minutes ne se déduit pas en faisant la moyenne des p95 affichés point par point.

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
| `contrat.ok` ; latence pour 1 000 lignes (champion, candidat) | `true` (20 features) ; 8,1 ms, 19,574 ms |
| AP globale champion, candidat ; écart et `ic95` | 0,8473 , 0,8854 ; 0,0381 [0,0333 ; 0,0429] |
| Segment le plus faible ; son écart et son `ic95` | activité client 7 j ≥ 20 ; 0,0212 [0,0159 ; 0,0268] |
| Segments non concluants | aucun : les six segments sont `concluant: true` |
| `rejeu` : désaccord, taux d'alerte champion et candidat | 0,0758 ; 0,1383 ; 0,1343 |
| Révision candidate ; version du modèle | à confirmer dans la table du trafic ; run `20261118T200052Z54cc32`, version 2 du registre |
| Verdict | favorable : contrat ok, AP +0,0381 avec un IC qui exclut 0, tous segments concluants ; à confirmer en ombre |

Avertissement lu dans `validation.txt` : août 2026 a servi à choisir les hyperparamètres du challenger,
donc les écarts sont optimistes pour lui. Seul le jeu de test, lu par `train.gate`, tranche.

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
| Panne (`next-1125145911` à 10 %) | ~14:00:50 | ~14:01:30 | `next-1125145911` | `candidate` | 1 / 1 | 648,1 / 2,3 | 0,0 % / 0,0 % | 100 % / 100 %* | non mesuré | retour arrière | p95 Cloud Run > 20 ms ou p95 app > 5 ms ; 3 timeouts client |
| Retour (`candidate` à 100 %) | ~14:01:40 | ~14:04:40 | `candidate` | `next` (arrêté) | 68 / 0 | 2,3 / — | 0,0 % / — | 100 %* / — | non mesuré | retour validé | p95 revenu à 2,3 ms |

\* La même transaction de test (`7c318…`) a été envoyée 100 fois : `tx distinctes` vaut 1 et le taux
d'alerte de 100 % n'est pas représentatif. Les p95, les erreurs et les dégradés sont valides.

En ombre : non mesuré dans cette reprise (l'ombre n'a pas été branchée). La validation donne 7,58 % de
désaccord sur août.

Panne : passage à 10 % vers 14:00:50 ; premier log `next-1125145911` à 14:01:00 (681,99 ms,
features 635,29) ; détection à ~14:01:30 sur `measure.py` (p95 648,1 ms contre 2,3 ms pour
`candidate`) ; délai ≈ 40 s ; signal : latence p95 (valeur 648,1 ms, borne de retour arrière
> 20 ms Cloud Run / > 5 ms applicatif) et 3 timeouts client (démarrage à froid). Retour vers
14:01:40 ; dernier log `next` à 14:01:13, aucun après.

Alias `champion` du registre : déjà sur la version 2 (`default`, `challenger`, `champion`), déplacé
lors de la séance. `promote.sh` n'a donc rien changé au trafic, ce qui est normal : l'alias désigne la
version du modèle, pas la répartition des révisions.

## Réponses aux questions

### Étape 2 — Validation et ombre

1. Écart global, son intervalle, effet de l'avertissement : +0,0381 [0,0333 ; 0,0429] en faveur du
   candidat. L'avertissement rappelle qu'août a servi au choix des hyperparamètres : l'écart est
   optimiste, seul le test de septembre tranche.
2. Segments non concluants, et pourquoi ne pas fonder le verdict sur eux : aucun segment n'est non
   concluant (tous ont au moins 30 fraudes). Le plus faible est « activité client 7 j ≥ 20 »
   (+0,0212 [0,0159 ; 0,0268]), encore favorable au candidat.
3. Désaccord en ombre comparé au `desaccord` de la validation, deux raisons d'écart : l'ombre n'a pas
   été mesurée ici. La validation donne 7,58 % sur août ; une ombre sur le flux réel peut différer
   parce que la population et les features du jour ne sont pas celles d'août, et parce que le seuil
   d'alerte est recalculé sur le candidat.
4. Ce que l'ombre apprend que la validation ne pouvait pas apprendre : le comportement sur les
   messages réels, la latence sous charge réelle et les valeurs de features du moment ; la validation
   ne voit qu'un mois historique figé.

### Étape 3 — Paliers

1. Transactions distinctes du candidat à 10 %, et si elles suffisent pour juger son taux d'alerte :
   les paliers 10/50/100 n'ont pas été rejoués dans cette reprise : la `candidate` était déjà à 100 %
   au début. Le test d'incident a envoyé une seule transaction distincte 100 fois ; il valide les
   latences, pas le taux d'alerte.
2. Signal le plus proche du seuil de retour arrière, et à quel palier : la latence p95 de `next`, au
   palier de panne à 10 % (648,1 ms contre une borne de 20 ms Cloud Run / 5 ms applicatif, plus 3 timeouts client).
3. Effet de `promote.sh` sur le trafic, et rôle de l'alias du registre : aucun effet sur le trafic ;
   l'alias `champion` désigne la version du modèle (ici la version 2), pas la répartition des
   révisions Cloud Run. Il permet à une nouvelle révision de charger la bonne version.

### Étape 4 — Panne

1. Premier signal sorti de sa bande ; signaux qui n'ont pas bougé : la latence p95 (et `features_ms`,
   606 ms chez `next` contre 1,46 ms chez `candidate`). Le taux d'erreur (0 %), les dégradés (0 %) et
   le taux d'alerte (100 % pour les deux, même transaction) n'ont pas bougé.
2. Signal qui aurait suffi seul ; signal qui ne l'aurait jamais vue : la latence p95 aurait suffi
   seule ; le taux d'erreur — et donc l'alerte `td6_failed` — ne l'aurait jamais vue, puisque la
   révision répondait 204 avec un score valide.
3. Transactions traitées par la révision `next` avant la détection ; ce qu'elle en aurait traité à
   100 % : 9 livraisons (1 transaction distincte, 3 timeouts client) avant la détection ; à 100 %, elle aurait traité
   les 100 requêtes du test.
