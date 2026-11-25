# Séance 4, preuve de la partie A : le rejeu de l'enseignant (ff-replay) était terminé, donc
# l'abonnement BigQuery n'avait rien reçu. Ce topic appartient à l'équipe : on y publie des
# transactions de test sans toucher au topic partagé, et l'abonnement tx_history les écrit seul.
resource "google_pubsub_topic" "history_proof" {
  name   = "${var.team}-tx-history-proof"
  labels = { team = var.team }
}
