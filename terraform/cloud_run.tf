resource "google_cloud_run_v2_service" "py_service" {
  name     = "py-service"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.py_image
      ports {
        container_port = 8000
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }
    }
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
  }
}

resource "google_cloud_run_v2_service" "go_service" {
  name     = "go-service"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.go_image
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
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
resource "google_cloud_run_v2_service_iam_member" "py_public" {
  name     = google_cloud_run_v2_service.py_service.name
  location = google_cloud_run_v2_service.py_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "go_public" {
  name     = google_cloud_run_v2_service.go_service.name
  location = google_cloud_run_v2_service.go_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
