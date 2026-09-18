# --- Serverless NEGs: bridge between Cloud Run services and the Load Balancer ---

resource "google_compute_region_network_endpoint_group" "python_fixed_time_api_serverless_neg" {
  name                  = "python-fixed-time-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.python_fixed_time_api.name
  }
}

resource "google_compute_region_network_endpoint_group" "go_fixed_time_api_serverless_neg" {
  name                  = "go-fixed-time-api-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.go_fixed_time_api.name
  }
}

# --- Backend services: one per app, each with its own Cloud CDN cache policy ---
# This is what satisfies "diferentes tempos de expiração": python = 10s, go = 60s.

resource "google_compute_backend_service" "python_fixed_time_api_backend_service" {
  name                  = "python-fixed-time-api-backend"
  protocol              = "HTTPS"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = true

  backend {
    group = google_compute_region_network_endpoint_group.python_fixed_time_api_serverless_neg.id
  }

  cdn_policy {
    cache_mode                   = "FORCE_CACHE_ALL"
    default_ttl                  = var.python_api_cache_ttl_seconds
    client_ttl                   = var.python_api_cache_ttl_seconds
    max_ttl                      = var.python_api_cache_ttl_seconds
    negative_caching             = false
    serve_while_stale            = 0
    signed_url_cache_max_age_sec = 0
  }
}

resource "google_compute_backend_service" "go_fixed_time_api_backend_service" {
  name                  = "go-fixed-time-api-backend"
  protocol              = "HTTPS"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = true

  backend {
    group = google_compute_region_network_endpoint_group.go_fixed_time_api_serverless_neg.id
  }

  cdn_policy {
    cache_mode                   = "FORCE_CACHE_ALL"
    default_ttl                  = var.go_api_cache_ttl_seconds
    client_ttl                   = var.go_api_cache_ttl_seconds
    max_ttl                      = var.go_api_cache_ttl_seconds
    negative_caching             = false
    serve_while_stale            = 0
    signed_url_cache_max_age_sec = 0
  }
}

# --- URL map: routes /python-api/* and /go-api/* to their respective backend+cache policy ---

resource "google_compute_url_map" "desafio_devops_lb" {
  name            = "desafio-devops-lb"
  default_service = google_compute_backend_service.python_fixed_time_api_backend_service.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "apps"
  }

  path_matcher {
    name            = "apps"
    default_service = google_compute_backend_service.python_fixed_time_api_backend_service.id

    path_rule {
      paths   = ["/python-api", "/python-api/*"]
      service = google_compute_backend_service.python_fixed_time_api_backend_service.id
    }

    path_rule {
      paths   = ["/go-api", "/go-api/*"]
      service = google_compute_backend_service.go_fixed_time_api_backend_service.id
    }
  }
}

resource "google_compute_managed_ssl_certificate" "desafio_devops_cert" {
  name = "desafio-devops-cert"
  managed {
    domains = ["desafio-devops.example.com"] # replace with a real domain before applying
  }
}

resource "google_compute_target_https_proxy" "desafio_devops_https_proxy" {
  name             = "desafio-devops-https-proxy"
  url_map          = google_compute_url_map.desafio_devops_lb.id
  ssl_certificates = [google_compute_managed_ssl_certificate.desafio_devops_cert.id]
}

resource "google_compute_global_address" "desafio_devops_lb_ip" {
  name = "desafio-devops-ip"
}

resource "google_compute_global_forwarding_rule" "desafio_devops_https_forwarding_rule" {
  name                  = "desafio-devops-forwarding-rule"
  target                = google_compute_target_https_proxy.desafio_devops_https_proxy.id
  ip_address            = google_compute_global_address.desafio_devops_lb_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
