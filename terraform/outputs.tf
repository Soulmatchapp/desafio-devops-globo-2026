output "load_balancer_ip" {
  description = "Public IP of the global load balancer. Point your domain's A record here."
  value       = google_compute_global_address.desafio_devops_lb_ip.address
}

output "python_fixed_time_api_url" {
  description = "Direct Cloud Run URL for python-fixed-time-api (bypasses CDN cache)."
  value       = google_cloud_run_v2_service.python_fixed_time_api.uri
}

output "go_fixed_time_api_url" {
  description = "Direct Cloud Run URL for go-fixed-time-api (bypasses CDN cache)."
  value       = google_cloud_run_v2_service.go_fixed_time_api.uri
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository to push images to."
  value       = google_artifact_registry_repository.desafio_devops_images.name
}
