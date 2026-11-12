terraform {
  backend "gcs" {
    bucket = "advanced-cloud-ai-tfstate"
    prefix = "team-really-cool" # team1, team-really-cool, team3 ou team-ghv
  }
}
