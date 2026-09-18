output "load_balancer_ip" {
  description = "Public IP of the global load balancer. Point your domain's A record here."
  value       = google_compute_global_address.desafio.address
}

output "py_service_url" {
  description = "Direct Cloud Run URL for py-service (bypasses CDN cache)."
  value       = google_cloud_run_v2_service.py_service.uri
}

output "go_service_url" {
  description = "Direct Cloud Run URL for go-service (bypasses CDN cache)."
  value       = google_cloud_run_v2_service.go_service.uri
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository to push images to."
  value       = google_artifact_registry_repository.desafio.name
}
