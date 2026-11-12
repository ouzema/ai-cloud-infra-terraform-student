# Socle commun, géré par l'enseignant : lecture seule.

data "google_artifact_registry_repository" "images" {
  repository_id = "cloud-ai"
  location      = var.region
}

data "google_storage_bucket" "models" {
  name = "${var.project_id}-models"
}

# Tranche de l'équipe : à écrire. Chaque nom commence par "${var.team}-".

# 1. Compte de service d'exécution : google_service_account

# 2. Ses droits, au plus juste :
#    - lire le bucket des modèles : google_storage_bucket_iam_member, roles/storage.objectViewer
#    - écrire des logs : google_project_iam_member, roles/logging.logWriter

# 3. Service Cloud Run : google_cloud_run_v2_service
#    - le conteneur écoute sur le port 8000
#    - le bucket des modèles est monté en volume, DATA_DIR pointe sur son dossier data/
#    - CPU, mémoire, concurrence, minimum et maximum d'instances

# 4. Qui peut appeler le service : google_cloud_run_v2_service_iam_member, roles/run.invoker
resource "google_service_account" "run" {
  account_id   = "${var.team}-run"
  display_name = "Execution du service ${var.team}"
}

resource "google_storage_bucket_iam_member" "models_reader" {
  bucket = data.google_storage_bucket.models.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.run.member
}

resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.run.member
}

resource "google_cloud_run_v2_service" "api" {
  name                = "${var.team}-fraud-api"
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.run.email
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    volumes {
      name = "models"
      gcs {
        bucket    = data.google_storage_bucket.models.name
        read_only = true
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "DATA_DIR"
        value = "/mnt/models/data"
      }
      env {
        name  = "WEB_CONCURRENCY"
        value = "1"
      }
      env {
        name  = "XGB_NTHREAD"
        value = "1"
      }

      volume_mounts {
        name       = "models"
        mount_path = "/mnt/models"
      }
    }
  }

  # le conteneur lit le bucket au démarrage : le droit doit exister avant
  depends_on = [google_storage_bucket_iam_member.models_reader]
}

resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.invokers)

  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = each.value
}
