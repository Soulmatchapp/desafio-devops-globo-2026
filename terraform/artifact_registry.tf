resource "google_artifact_registry_repository" "desafio_devops_images" {
  location      = var.region
  repository_id = "desafio-devops"
  description   = "Container images for the DevOps challenge apps"
  format        = "DOCKER"
}
