resource "google_cloud_run_v2_service" "python_fixed_time_api" {
  name     = "python-fixed-time-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.python_api_container_image
      ports {
        container_port = 8000
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

resource "google_cloud_run_v2_service" "go_fixed_time_api" {
  name     = "go-fixed-time-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.go_api_container_image
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

# Allow unauthenticated invocations so the LB/CDN in front can be reached publicly.
# Improvement point: restrict this with Cloud Armor / IAP and keep Cloud Run private,
# only reachable through the Serverless NEG (see README "Pontos de melhoria").
resource "google_cloud_run_v2_service_iam_member" "python_fixed_time_api_public_invoker" {
  name     = google_cloud_run_v2_service.python_fixed_time_api.name
  location = google_cloud_run_v2_service.python_fixed_time_api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "go_fixed_time_api_public_invoker" {
  name     = google_cloud_run_v2_service.go_fixed_time_api.name
  location = google_cloud_run_v2_service.go_fixed_time_api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# cache-reverse-proxy: public entrypoint that fronts both apps with the same
# 10s/60s cache TTLs as the local docker-compose setup, without needing a
# Load Balancer + Cloud CDN + custom domain (see nginx/nginx-cloud.conf).
resource "google_cloud_run_v2_service" "cache_reverse_proxy" {
  name     = "cache-reverse-proxy"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.cache_reverse_proxy_container_image
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.python_fixed_time_api_public_invoker,
    google_cloud_run_v2_service_iam_member.go_fixed_time_api_public_invoker,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "cache_reverse_proxy_public_invoker" {
  name     = google_cloud_run_v2_service.cache_reverse_proxy.name
  location = google_cloud_run_v2_service.cache_reverse_proxy.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
