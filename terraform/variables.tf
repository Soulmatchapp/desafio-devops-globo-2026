variable "project_id" {
  description = "GCP project ID where the challenge infra will be provisioned."
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run and Artifact Registry."
  type        = string
  default     = "southamerica-east1"
}

variable "py_image" {
  description = "Full Artifact Registry image reference for py-service (e.g. REGION-docker.pkg.dev/PROJECT/desafio-devops/py-service:latest)."
  type        = string
}

variable "go_image" {
  description = "Full Artifact Registry image reference for go-service."
  type        = string
}

variable "py_cache_ttl_seconds" {
  description = "Cloud CDN cache TTL for the Python service (challenge requires 10s)."
  type        = number
  default     = 10
}

variable "go_cache_ttl_seconds" {
  description = "Cloud CDN cache TTL for the Go service (challenge requires 1 minute)."
  type        = number
  default     = 60
}
