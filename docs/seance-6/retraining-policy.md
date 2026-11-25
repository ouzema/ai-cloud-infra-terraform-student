# Politique de réentraînement — team-really-cool

- **Déclencheur principal (calendrier).** Réentraînement hebdomadaire, lundi 02:00 UTC, sur
  `train-large` jusqu'au dernier mois dont les labels sont matures. Le modèle produit est un
  challenger : il ne remplace le champion qu'après la porte d'entrée.
- **Dérive (anticipation).** Alerte si le PSI dépasse 0,25 sur le montant (`TX_AMOUNT`), l'activité
  client à 7 jours ou le taux de fraude terminal, entre une fenêtre de référence et la semaine
  courante. Une dérive déclenche une étude, puis un challenger si elle est confirmée.
- **Performance (juge).** Si l'AP sur labels matures (7 jours de retard) baisse de plus de 0,01 par
  rapport au champion sur deux semaines consécutives, un challenger est entraîné et passé à la porte.
- **Porte d'entrée.** `train.gate` lit le test de septembre **une seule fois**, compare le candidat au
  champion sur les mêmes transactions (bootstrap apparié, 200 rééchantillonnages, IC 95 %) et
  n'enregistre le challenger que si la borne basse de l'écart d'AP est > 0,003. Un refus est un
  résultat recevable et est journalisé dans `runs/team-really-cool/decisions/`.
- **Responsables.** Entraînement et metadata : ML engineer de l'équipe. Données, features et
  disponibilité des labels : data engineer. Release, surveillance et retour arrière : ingénieur
  d'astreinte. Seuil métier et politique de fraude : analyste fraude / product owner. Registre,
  alias `champion`/`challenger` et porte : team lead.
- **Labels et découpage.** Les labels de fraude arrivent avec 7 jours de retard. On n'entraîne jamais
  sur un mois dont les labels ne sont pas matures ; le découpage reste temporel (juin–juillet pour
  l'entraînement, août pour le choix des hyperparamètres, septembre pour le test, lu une seule fois).
