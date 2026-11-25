# Séance 6, « Après le TD » : description en lecture seule du service team-really-cool-scorer.
#
# Ce dossier a son propre état, local : pas de backend. On ne l'applique jamais.
# Le service appartient au socle ; un apply ou un destroy depuis infra/ le supprimerait
# ou lui imposerait notre configuration. La commande attendue est :
#   terraform init
#   terraform plan -generate-config-out=scorer.tf
# puis on ajoute lifecycle { prevent_destroy = true } dans la ressource générée.

terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

provider "google" {
  project = "advanced-cloud-ai"
  region  = "europe-west1"

  # Sans cette ligne, le provider ajoute un libellé au service et le plan annonce
  # une modification au lieu d'un import propre.
  add_terraform_attribution_label = false
}

import {
  to = google_cloud_run_v2_service.scorer
  id = "projects/advanced-cloud-ai/locations/europe-west1/services/team-really-cool-scorer"
}
