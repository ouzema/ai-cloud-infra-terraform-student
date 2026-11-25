# Séance 4, partie D : une base vectorielle (Qdrant) sur Cloud Run, pour les justificatifs KYC.
#
# Choix de dimensionnement :
#   * min_instance_count = 1 et max_instance_count = 1 : l'index HNSW vit dans la mémoire
#     d'une instance. Deux instances répondraient avec deux index différents, et une
#     instance à zéro perdrait l'index à chaque arrêt ;
#   * cpu_idle = false : l'instance reste allouée, sinon Cloud Run peut la mettre en veille
#     et l'index doit être rechargé.

resource "google_cloud_run_v2_service" "vectors" {
  name                = "${var.team}-vectors"
  location            = var.region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = "docker.io/qdrant/qdrant:v1.12.4"

      ports {
        container_port = 6333
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
        cpu_idle = false
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "vectors_invokers" {
  for_each = toset(var.invokers)
  name     = google_cloud_run_v2_service.vectors.name
  location = var.region
  role     = "roles/run.invoker"
  member   = each.value
}

output "vectors_url" {
  value = google_cloud_run_v2_service.vectors.uri
}
