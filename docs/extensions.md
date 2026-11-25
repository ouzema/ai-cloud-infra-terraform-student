# Extensions — team-really-cool

Oussema ARIBI, Yann MEUROU, Elisa CHEN. Une entrée par extension : domaine, ce qui a été construit,
comment le voir fonctionner, limites.

## 1. Déploiement continu (Déploiement) — Oussema ARIBI

- **Construit :** `.github/workflows/deploy.yml` (commit `99cc6e8`). Un `git push` sur `main` construit
  l'image depuis `td2-fraud-api-albertschool`, la pousse en `team-really-cool-fraud-api:<sha>` et
  déploie une nouvelle révision. Authentification par Workload Identity Federation (jeton OIDC
  GitHub échangé contre `team-really-cool-cd`), sans clé de compte de service.
- **Voir :** onglet *Actions* du fork, puis
  `gcloud run revisions list --service team-really-cool-fraud-api --region europe-west1`.
- **Limites :** pas de test de fumée bloquant avant la bascule du trafic ; le tag d'image est le sha
  de ce dépôt, pas celui du code applicatif.

## 2. Terraform et déploiement continu sans conflit (Terraform) — Oussema ARIBI

- **Construit :** bloc `lifecycle { ignore_changes = [template[0].containers[0].image] }` dans
  `infra/main.tf` (commit `62afa2d`). Terraform garde la main sur le compte, les droits et les
  réglages ; le workflow garde la main sur l'image.
- **Voir :** après un déploiement par le workflow, `cd infra && terraform plan` ne propose pas de
  revenir à l'image de `terraform.tfvars`.
- **Limites :** un changement d'image volontaire par Terraform est ignoré lui aussi ; la variable
  `image` ne sert plus qu'à la création.

## 3. Alerte qui aurait détecté l'incident (Monitoring) — Yann MEUROU

- **Construit :** `infra/release.tf` (commit `09acf12`) : règle d'alerte sur
  `run.googleapis.com/request_latencies`, p95 > 50 ms pendant 60 s, par révision. L'ancienne règle
  sur `td6_failed` n'aurait jamais vu l'incident `next` (aucun échec, seulement de la latence).
- **Voir :** Console → Monitoring → Alerting ; elle se déclenche sur la régression `next`
  (p95 648 ms, `docs/seance-6/post-mortem.md`).
- **Limites :** seuil 50 ms au-dessus de notre seuil de retour (20 ms) pour ne pas réagir à un cold
  start isolé ; elle alerte, elle ne fait pas le retour arrière.

## 4. Mode dégradé (Cycle de vie du modèle) — Elisa CHEN

- **Construit :** test de la panne de lecture des features sur le tag `degrade`
  (`FEATURE_READER=direct`, `BQ_DATASET=does_not_exist`) avec les deux politiques du service
  (commit `9707ebb`, `docs/seance-6/mesures.md`, section *Mode dégradé*). `allow` : 100 % dégradés,
  0 % d'alertes ; `block` : 100 % dégradés, 100 % d'alertes. Choix : `allow` + surveillance du taux
  de dégradés.
- **Voir :** le tableau de la section dans `mesures.md` ; démonstration en rejouant les variables
  sur le tag `degrade`.
- **Limites :** 10 messages par politique ; pas d'alerte automatique sur le taux de dégradés.

## 5. Politique de réentraînement (Cycle de vie du modèle) — Yann MEUROU

- **Construit :** `docs/seance-6/retraining-policy.md` (commit `9707ebb`) : calendrier hebdomadaire,
  déclenchement sur dérive (PSI) et sur performance (AP sur labels matures), porte d'entrée à 0,003,
  responsable par rôle.
- **Voir :** le document ; la porte est celle appliquée en séance 5 (`docs/seance-5/compte-rendu.md`).
- **Limites :** politique écrite, pas automatisée : aucun job planifié ne la déclenche.

## 6. Service du socle décrit et restaurable (Terraform) — Elisa CHEN

- **Construit :** `infra/scorer/` (commit `09acf12`) importe `team-really-cool-scorer` en lecture
  seule ; `docs/seance-6/plan.txt` montre `1 to import, 0 to add, 0 to change, 0 to destroy`. Exercice
  de restauration du 25/11 : modèle version 2 copié puis supprimé, `customer_daily` et
  `terminal_daily` restaurées par time travel (903 359 / 119 640 lignes).
- **Voir :** `cd infra/scorer && terraform init && terraform plan` (jamais `apply`, voir le README).
- **Limites :** `template.revision` (`next`) n'est pas la révision qui sert (`candidate`) ; le
  service appartient au socle, nous ne pouvons pas le recréer nous-mêmes.
