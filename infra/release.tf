# Séance 6, « Après le TD » : l'abonnement d'ombre et la règle d'alerte de votre équipe.
# À copier dans infra/release.tf. Il utilise var.team, var.project_id et var.region de infra/variables.tf.
# La règle d'alerte surveille la latence p95 Cloud Run par révision : plus de 50 ms
# pendant 60 s. Voir le commentaire du bloc condition_threshold pour le raisonnement.

variable "shadow_tag" {
  description = "Tag de la révision qui reçoit l'ombre (candidate, degrade...). Vide : pas d'abonnement d'ombre."
  type        = string
  default     = ""
}

data "google_cloud_run_v2_service" "scorer" {
  name     = "${var.team}-scorer"
  location = var.region
}

locals {
  shadow_url = one([
    for t in data.google_cloud_run_v2_service.scorer.traffic_statuses : t.uri if t.tag == var.shadow_tag
  ])
}

# Mêmes réglages que shadow.sh. L'audience est l'adresse du service, pas celle du tag.
resource "google_pubsub_subscription" "shadow" {
  count = var.shadow_tag == "" ? 0 : 1

  name  = "${var.team}-shadow"
  topic = "projects/${var.project_id}/topics/ff-td6"

  ack_deadline_seconds       = 30
  message_retention_duration = "3600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  push_config {
    push_endpoint = "${local.shadow_url}/pubsub/shadow"

    oidc_token {
      service_account_email = "${var.team}-scorer-push@${var.project_id}.iam.gserviceaccount.com"
      audience              = data.google_cloud_run_v2_service.scorer.uri
    }
  }

  lifecycle {
    precondition {
      condition     = local.shadow_url != null
      error_message = "Le tag ${var.shadow_tag} n'existe pas sur ${var.team}-scorer."
    }
  }
}

# Le projet n'a pas de canal de notification : la règle ouvre un incident dans Monitoring → Alertes.
resource "google_monitoring_alert_policy" "release" {
  display_name = "${var.team}-scorer-release"
  combiner     = "OR"

  user_labels = {
    team = var.team
  }

  conditions {
    display_name = "${var.team}-scorer, par révision"

    condition_threshold {
      # Signal choisi : la latence p95 des requêtes, par révision.
      # L'incident de la séance est une régression de latence : la révision `next`
      # (FEATURE_READER=direct) répondait 204 avec un score valide, mais p95 564 ms
      # contre 3,1 ms pour `candidate`. Une alerte sur td6_failed ne l'aurait jamais vue.
      # La latence Cloud Run est disponible sans code, par révision, et couvre ce cas.
      filter = "metric.type=\"run.googleapis.com/request_latencies\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.team}-scorer\""

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["resource.label.revision_name"]
      }

      comparison = "COMPARISON_GT"

      # Seuil : 50 ms de p95 par révision. La référence saine est ~10 ms côté Cloud Run
      # (3,1 ms applicatif) ; 50 ms laisse passer un cold start isolé et déclenche sur
      # une régression comme celle de `next` (564 ms).
      threshold_value = 50

      # Durée : 60 s au-dessus du seuil. Une minute suffit à voir la régression sans
      # attendre cinq minutes de trafic dégradé.
      duration = "60s"

      trigger {
        count = 1
      }
    }
  }
}
