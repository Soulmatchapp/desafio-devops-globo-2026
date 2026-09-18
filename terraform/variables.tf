variable "project_id" {
  description = "GCP project ID where the challenge infra will be provisioned."
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run and Artifact Registry."
  type        = string
  default     = "southamerica-east1"
}

variable "python_api_container_image" {
  description = "Full Artifact Registry image reference for python-fixed-time-api (e.g. REGION-docker.pkg.dev/PROJECT/desafio-devops/python-fixed-time-api:latest)."
  type        = string
}

variable "go_api_container_image" {
  description = "Full Artifact Registry image reference for go-fixed-time-api."
  type        = string
}

variable "cache_reverse_proxy_container_image" {
  description = "Full Artifact Registry image reference for cache-reverse-proxy (Nginx variant that proxies to the public Cloud Run URLs of the two apps)."
  type        = string
}

variable "python_api_cache_ttl_seconds" {
  description = "Cloud CDN cache TTL for python-fixed-time-api (challenge requires 10 seconds)."
  type        = number
  default     = 10
}

variable "go_api_cache_ttl_seconds" {
  description = "Cloud CDN cache TTL for go-fixed-time-api (challenge requires 1 minute)."
  type        = number
  default     = 60
}
