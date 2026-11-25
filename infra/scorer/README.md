# `infra/scorer` — description en lecture seule de `team-really-cool-scorer`

Ce dossier décrit le service Cloud Run **du socle** (`team-really-cool-scorer`) pour pouvoir le
relire, le versionner et le reconstruire. Il ne faut **jamais** l'appliquer ni le détruire : le
service appartient à l'enseignant et un `apply`/`destroy` ici le supprimerait ou lui imposerait notre
configuration.

## Procédure

```bash
cd infra/scorer
terraform init
terraform plan -generate-config-out=scorer.tf
```

`scorer.tf` est généré à partir de l'état réel. Ensuite :

1. ajouter dans la ressource générée :

   ```hcl
   lifecycle {
     prevent_destroy = true
   }
   ```

2. relire les blocs `traffic` : ils doivent nommer la révision qui sert et ses tags ;
3. comparer `template.revision` (dernière révision créée) à la révision qui porte 100 % du trafic :
   après un retour arrière, ce ne sont pas forcément les mêmes ;
4. relancer le plan et enregistrer la sortie :

   ```bash
   terraform plan -no-color | tee ../../docs/seance-6/plan.txt
   ```

5. masquer les adresses `creator` et `last_modifier` dans `plan.txt` avant le commit.

L'état de ce dossier est **local** : pas de bloc `backend`.
