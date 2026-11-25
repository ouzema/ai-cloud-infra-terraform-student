# Compte rendu séance 5 — team-really-cool

**Qui a fait quoi.** Yann MEUROU : job d'entraînement reproductible (`infra/job.tf`, `metadata.json`) et recherche à 1, 4 et 8 workers ; Elisa CHEN : coût des recherches et du run 12 mois ; Oussema ARIBI : run 12 mois, porte d'entrée et décision au registre.

| Mesure | Valeur |
| --- | --- |
| Étape 0 : lignes relues dans `MANIFEST.json` (`train-sample`, `valid`, `test`) ; version et alias du modèle en place | 611 548, 311 624, 301 545 ; version 1, alias `champion` |
| Étape 1 : `run_id`, commit, image, graine, AP de validation | `20261118T181018Zdbf781` ; `8c2691192d9cb5604b54bb8e9e605fac78a077c0` ; `fraud-train:td5` ; 42 ; 0,8512 |
| Étape 1 : durée de l'exécution ; `load` et `fit` de `metadata.json` | 88,5 s ; 17,85 s, 24,87 s (évaluation 1,95 s) |
| Étape 3 : `run_id` du modèle 12 mois ; `fit` ; AP de validation | `20261118T200052Z54cc32` (Cloud Run, secours) ; 549,8 s ; 0,8854 |
| Étape 3 : AP test candidat et champion ; écart et IC à 95 % ; verdict | 0,8780, 0,8421 ; 0,0355 [0,0309 ; 0,0403] ; accepté |
| Étape 3 : version au registre (ou « refus ») ; `rang_lecture_test` | version 2, alias `challenger` (champion v1 inchangé) ; 1 |
| Étape 4 : débits DDP à 1 et 2 processus ; AP de validation | non relevé — démonstration de l'enseignant, valeurs non consignées ; compte rendu complet par ailleurs |
| Lien du dépôt (`infra/job.tf`) | https://github.com/ouzema/ai-cloud-infra-terraform-student/blob/main/infra/job.tf |

## Recherche (étape 2)

| Étude | Workers | vCPU par tâche | Threads | Essais terminés | `wall_seconds` | Durée de l'exécution | `sum_fit_seconds` | Meilleure AP | Tâches réussies / lancées |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| w1-t1 | 1 | 1 | 1 | 40 | 1 417,2 | 1 482,3 | 1 309,1 | 0,8561 | 1 / 1 |
| w4-t1 | 4 | 1 | 1 | 43 | 373,9 | 433,5 | 1 310,8 | 0,8557 | 4 / 4 |
| w8-t1 | 8 | 1 | 1 | 47 | 218,5 | 257,5 | 1 398,8 | 0,8551 | 8 / 8 |
| w4-t4 | 4 | 4 | 4 | 43 | 195,8 | 274,9 | 568,2 | 0,8564 | 4 / 4 |

La quatrième configuration a été lancée après la fin de w4-t1 et w8-t1, sur son étude `w4-t4`
(4 vCPU et 4 threads par tâche).

Courbe d'accélération : [`courbe-acceleration.svg`](courbe-acceleration.svg), avec la droite idéale
y = n. J'utilise **`wall_seconds`** pour la courbe : c'est la durée du travail de recherche lui-même
(du début du premier essai à la fin du dernier), donc la grandeur que le parallélisme doit réduire.
La durée de l'exécution, plus longue, ajoute le démarrage, la lecture des données et l'écriture des
résultats, qui sont une part fixe non parallélisable ; c'est elle qui sert au coût (§ ci-dessous).

Accélération mesurée (durée à 1 worker / durée à n workers) :

| Workers | `wall_seconds` | Accélération (wall) | Efficacité | Durée d'exécution | Accélération (exécution) |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 417,2 s | 1,00× | 100 % | 1 482,3 s | 1,00× |
| 4 | 373,9 s | 3,79× | 94,8 % | 433,5 s | 3,42× |
| 8 | 218,5 s | 6,49× | 81,1 % | 257,5 s | 5,76× |
| 4 (× 4 vCPU) | 195,8 s | 7,24× | — | 274,9 s | 5,39× |

La dernière ligne (`w4-t4`) n'est pas comparable directement aux autres : elle utilise 4 vCPU
par tâche au lieu d'un. Rapportée à `w4-t1`, elle est 1,91× plus rapide pour 4× plus de vCPU, soit
une efficacité de 48 % des vCPU ajoutés. Les 4 threads réduisent le `fit` d'un essai de 30,5 s à
13,2 s (2,31×) et `sum_fit_seconds` de 1 311 s à 568 s.

## Coût des recherches

Prix relevés le **18 novembre 2026** sur <https://cloud.google.com/run/pricing>, section **Jobs**,
région `europe-west1` (Tier 1) : **0,000018 USD par vCPU-seconde** et **0,000002 USD par
GiB-seconde**. Un job Cloud Run est facturé à l'instance, pendant toute la durée de vie de chaque
tâche, avec un minimum de 1 minute par instance.

Formule : `coût = tâches × durée_exécution × (vCPU × 0,000018 + GiB × 0,000002)`.

Hypothèses : durée = `startTime` → `completionTime` de l'exécution (démarrage du conteneur, lecture
des données, recherche, écriture des résultats) ; toutes les tâches tournent en même temps ; prix
hors taxes et sans remise ; on exclut les opérations Cloud Storage, l'egress VPC, la base Optuna
(fournie par le socle) et le stockage des images. Le niveau gratuit mensuel de Cloud Run Jobs
(240 000 vCPU-s et 450 000 GiB-s) n'est pas déduit : le coût brut est celui ci-dessous, le coût
marginal facturé de ces quatre recherches est en réalité de 0 USD.

| Étude | Tâches | vCPU / tâche | GiB / tâche | Durée (s) | vCPU-s | GiB-s | Coût brut (USD) | Coût par essai (USD) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| w1-t1 | 1 | 1 | 2 | 1 482,3 | 1 482 | 2 965 | 0,0326 | 0,00082 |
| w4-t1 | 4 | 1 | 2 | 433,5 | 1 734 | 3 468 | 0,0381 | 0,00089 |
| w8-t1 | 8 | 1 | 2 | 257,5 | 2 060 | 4 121 | 0,0453 | 0,00096 |
| w4-t4 | 4 | 4 | 8 | 274,9 | 4 399 | 8 797 | 0,0968 | 0,00225 |
| **Total** | | | | | 9 675 | 19 350 | **0,2129** | |

## Entraînement final (étape 3, 12 mois)

Le custom job Vertex AI `team-really-cool-train-large-2025-08-n2-standard-8-t8` reprend les
meilleurs hyperparamètres de l'étude **w1-t1**, choisie au moment de la soumission (avant la fin
de w4-t4) et meilleure AP des études à 1 thread. Il porte sur les 12 mois
`train-large/2025-08` à `2026-07` : 36 629 935 lignes, soit 59,9× plus que `train-sample`.

**Incident de capacité Vertex AI.** Le custom job a été soumis en `europe-west1` puis, après
annulation, en `europe-west4` : les deux sont restés `JOB_STATE_PENDING` (aucun log de conteneur,
aucun `startTime` en `europe-west1`) pendant que deux jobs `team1` occupaient les créneaux de
calcul du projet. Pour ne pas bloquer la décision, le même entraînement a été exécuté avec la
**même image, le même compte de service, les mêmes données, les mêmes hyperparamètres et 8
threads** en job Cloud Run (`team-really-cool-train-large-jkt5g`, 8 vCPU, 32 GiB), qui écrit dans
le même dossier `runs/team-really-cool/models/`. Seule la plateforme d'exécution diffère ; le
`metadata.json` produit est celui du run ci-dessous et c'est lui qui est présenté à la porte
d'entrée.

| Threads | `rows.train` | `load` | `fit` | AP de validation |
| --- | --- | --- | --- | --- |
| 8 | 36 629 935 | 850,7 s | 549,8 s | 0,8854 |

Lecture : par rapport à l'étape 1 (17,85 s de `load` et 24,87 s de `fit` sur 611 548 lignes), le
`load` est multiplié par 47,7 et le `fit` par 22,1, alors que les lignes sont multipliées par 59,9.
Le `load` augmente donc le plus : il lit 12 fichiers à travers GCSFuse et n'est pas parallélisé par
les threads. Le `fit`, lui, profite des 8 threads et de paramètres plus lourds (365 arbres,
profondeur 10) : le temps par ligne passe de 40,7 µs à 15,0 µs, soit 2,7× moins. Sans les threads,
60× plus de lignes auraient coûté environ 60× plus de temps de `fit`.

Coût de ce run de secours : 8 vCPU et 32 GiB pendant 1 424,5 s, soit
`1 424,5 × (8 × 0,000018 + 32 × 0,000002) = 0,296 USD` brut (11 396 vCPU-s et 45 585 GiB-s, dans le
niveau gratuit). Le custom job Vertex AI n'a pas été facturé puisqu'il n'a jamais démarré.

## Six questions

1. **Quelles données, quel code et quelle configuration ont produit notre modèle ?**
   `metadata.json` identifie l'instantané des données (nombre de lignes et `sha256` de
   `train-sample.parquet` et `valid.parquet`, noms des 20 features, fenêtres 1/7/14 jours, délai de
   label 7 jours), le code (`git_commit`), l'image (`fraud-train:td5`), les hyperparamètres
   (`n_estimators`, `max_depth`, `learning_rate`, `subsample`, `colsample_bytree`,
   `min_child_weight`, objectif), la graine 42, les versions (Python 3.13.18, XGBoost 3.4.1,
   NumPy 2.5.4) et le nombre de CPU de la machine. Un tiers peut donc rejouer la même recette sur
   les mêmes données. Pour obtenir le même modèle **au bit près**, il lui manque le digest de
   l'image (le tag `td5` peut bouger), le modèle exact de CPU (les opérations flottantes et le
   découpage des histogrammes XGBoost peuvent différer), les options de déterminisme et l'ordre
   exact des lignes ; une reproductibilité bit à bit n'est pas garantie d'une machine à l'autre.
   Le jeu de test n'apparaît pas : c'est voulu, il est réservé à la porte d'entrée.

2. **Combien de temps prend la recherche avec un, quatre et huit workers ?**
   23 min 37 s (`wall_seconds` 1 417 s ; 24 min 42 s d'exécution) à 1 worker, 6 min 14 s
   (7 min 14 s) à 4 workers et 3 min 38 s (4 min 18 s) à 8 workers. L'accélération est de 3,79× à
   4 workers et 6,49× à 8 workers sur `wall_seconds` (3,42× et 5,76× sur la durée facturée).

3. **Pourquoi le gain n'est-il pas proportionnel au nombre de workers ?**
   Trois causes, visibles dans nos chiffres. (a) Une part fixe par exécution : 65 s, 60 s et 39 s
   d'écart entre durée d'exécution et `wall_seconds` (démarrage, lecture des données, écriture des
   résultats), incompressible. (b) Le travail total d'entraînement ne diminue pas : `sum_fit_seconds`
   vaut 1 309 s, 1 311 s et 1 399 s ; à 8 workers il augmente même de 7 %, parce que l'exécution
   termine 47 essais au lieu de 40 et que les workers se disputent la base Optuna. (c) Le découpage
   se fait par essais entiers : chaque worker finit l'essai en cours, et le plus lent impose la fin.
   À 4 workers, les essais par worker vont de 9 à 12 ; à 8, de 5 à 7. C'est pour cela qu'on termine
   43 et 47 essais, et que le dernier essai du worker le plus chargé coûte cher. Au total,
   `wall ≈ sum_fit / workers + overhead de recherche + queue de fin` : 1 417 ≈ 1 309 + 108,
   374 ≈ 1 311/4 + 46, 218 ≈ 1 399/8 + 44 ; et 196 ≈ 568/4 + 54 pour w4-t4. La durée facturée
   ajoute ensuite la part fixe (démarrage, lecture, écriture) relevée en (a). La configuration
   w4-t4 montre la même mécanique avec des essais plus courts (13,2 s de `fit`), mais la répartition
   est très inégale (6, 8, 11 et 18 essais par worker, selon la durée des hyperparamètres tirés).

4. **Combien a coûté notre recherche, et avec quelles hypothèses ?**
   0,0326 USD à 1 worker, 0,0381 USD à 4 workers, 0,0453 USD à 8 workers (0,00082 à
   0,00096 USD par essai) et 0,0968 USD pour la configuration 4 vCPU × 4 threads (0,00225 USD par
   essai). Le total des quatre recherches est de 0,2129 USD brut. Le calcul utilise
   0,000018 USD/vCPU-s et 0,000002 USD/GiB-s
   (relevé du 18/11/2026), la durée de vie facturée de chaque tâche et 2 GiB par tâche (8 GiB pour
   w4-t4), sans compter le stockage, la base Optuna ni l'egress. Plus de workers ne coûte pas moins
   cher : le temps baisse, mais la part fixe est payée par tâche et les essais supplémentaires
   augmentent le travail total. Le niveau gratuit couvre largement ces volumes.

5. **Le modèle entre-t-il au registre, et sur quelle base ?**
   Oui. Sur le test de septembre 2026 (301 545 transactions, lues une seule fois :
   `rang_lecture_test` = 1), l'AP du candidat est 0,8780 contre 0,8421 pour le champion. L'écart
   est de 0,0355, avec un intervalle de confiance à 95 % de [0,0309 ; 0,0403] par bootstrap
   apparié (200 rééchantillonnages). La borne basse, 0,0309, est supérieure à la marge de 0,003 :
   le verdict est **accepté**. Le candidat est enregistré comme version **2** de
   `fraud-scorer-team-really-cool` avec l'alias **`challenger`** ; la version 1 garde l'alias
   `champion`.

6. **Démonstration DDP : qu'apporte le second processus, et pourquoi ?**
   DDP réplique sur chaque processus une copie complète du modèle, des gradients et de l'état de
   l'optimiseur ; il ne partage que les données, découpées en tranches. Chaque processus calcule le
   gradient sur sa tranche, puis un `all-reduce` (anneau) moyenne les gradients avant la mise à
   jour : les répliques restent identiques. Le second processus divise donc le travail de calcul par
   deux, mais le débit ne double pas : il faut synchroniser à chaque pas (communication), charger
   les données, et le processus le plus lent impose sa vitesse ; sur un petit modèle CPU, le coût
   de l'`all-reduce` et du démarrage n'est pas négligeable. DDP ne réduit pas la mémoire par
   processus, puisque le modèle est entier sur chacun. FSDP ou ZeRO (sharding des paramètres,
   gradients et états de l'optimiseur) s'impose quand le modèle ne tient plus dans la mémoire d'un
   processus, ou pour entraîner un modèle beaucoup plus grand : on échange alors plus de
   communication contre de la mémoire.

   Réponse individuelle — Yann MEUROU : le second processus apporte du débit de calcul parallèle, pas de
   la mémoire. Le débit ne double pas à cause de l'`all-reduce`, de la synchronisation et du
   chargement des données ; FSDP/ZeRO devient nécessaire dès que le modèle complet ne tient plus
   sur un seul processus.

   Réponse individuelle — Oussema ARIBI : *à écrire et signer par Oussema.*

   Réponse individuelle — Elisa CHEN : *à écrire et signer par Elisa.*

**Note étape 4 :** les deux débits (échantillons/s) et les AP de validation à 1 et 2 processus n'ont
pas été notés pendant la démonstration de l'enseignant ; ils ne figurent ni dans le dépôt ni dans les
logs. Chaque étudiant ajoute sa réponse individuelle signée.

**Statut du compte rendu : complet.** Les quatre valeurs DDP restent non relevées ; tout le reste
est mesuré et documenté.
