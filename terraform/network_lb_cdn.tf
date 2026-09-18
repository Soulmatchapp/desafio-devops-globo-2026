# --- Serverless NEGs: bridge between Cloud Run services and the Load Balancer ---

resource "google_compute_region_network_endpoint_group" "py_neg" {
  name                  = "py-service-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.py_service.name
  }
}

resource "google_compute_region_network_endpoint_group" "go_neg" {
  name                  = "go-service-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.go_service.name
  }
}

# --- Backend services: one per app, each with its own Cloud CDN cache policy ---
# This is what satisfies "diferentes tempos de expiração": py = 10s, go = 60s.

resource "google_compute_backend_service" "py_backend" {
  name                  = "py-service-backend"
  protocol              = "HTTPS"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = true

  backend {
    group = google_compute_region_network_endpoint_group.py_neg.id
  }

  cdn_policy {
    cache_mode        = "FORCE_CACHE_ALL"
    default_ttl       = var.py_cache_ttl_seconds
    client_ttl        = var.py_cache_ttl_seconds
    max_ttl           = var.py_cache_ttl_seconds
    negative_caching  = false
    serve_while_stale = 0
  }
}

resource "google_compute_backend_service" "go_backend" {
  name                  = "go-service-backend"
  protocol              = "HTTPS"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = true

  backend {
    group = google_compute_region_network_endpoint_group.go_neg.id
  }

  cdn_policy {
    cache_mode        = "FORCE_CACHE_ALL"
    default_ttl       = var.go_cache_ttl_seconds
    client_ttl        = var.go_cache_ttl_seconds
    max_ttl           = var.go_cache_ttl_seconds
    negative_caching  = false
    serve_while_stale = 0
  }
}

# --- URL map: routes /py/* and /go/* to their respective backend+cache policy ---

resource "google_compute_url_map" "desafio" {
  name            = "desafio-devops-lb"
  default_service = google_compute_backend_service.py_backend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "apps"
  }

  path_matcher {
    name            = "apps"
    default_service = google_compute_backend_service.py_backend.id

    path_rule {
      paths   = ["/py", "/py/*"]
      service = google_compute_backend_service.py_backend.id
    }

    path_rule {
      paths   = ["/go", "/go/*"]
      service = google_compute_backend_service.go_backend.id
    }
  }
}

resource "google_compute_managed_ssl_certificate" "desafio" {
  name = "desafio-devops-cert"
  managed {
    domains = ["desafio-devops.example.com"] # replace with a real domain before applying
  }
}

resource "google_compute_target_https_proxy" "desafio" {
  name             = "desafio-devops-https-proxy"
  url_map          = google_compute_url_map.desafio.id
  ssl_certificates = [google_compute_managed_ssl_certificate.desafio.id]
}

resource "google_compute_global_address" "desafio" {
  name = "desafio-devops-ip"
}

resource "google_compute_global_forwarding_rule" "desafio" {
  name                  = "desafio-devops-forwarding-rule"
  target                = google_compute_target_https_proxy.desafio.id
  ip_address            = google_compute_global_address.desafio.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
