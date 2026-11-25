# Séance 4, partie C : droits du compte d'exécution pour lire les compteurs hors du conteneur.
# Le compte est celui de main.tf ; on réutilise son attribut member pour ne pas coder
# l'adresse en dur et garder une seule source de vérité.

locals {
  run_member = google_service_account.run.member
}

# Lire les tables de votre dataset.
resource "google_bigquery_dataset_iam_member" "run_reads_dataset" {
  dataset_id = local.dataset
  role       = "roles/bigquery.dataViewer"
  member     = local.run_member
}

# Lancer des requêtes BigQuery, lire et écrire dans Firestore.
resource "google_project_iam_member" "run_feature_stores" {
  for_each = toset(["roles/bigquery.jobUser", "roles/datastore.user"])
  project  = var.project_id
  role     = each.value
  member   = local.run_member
}
