resource "google_project_service" "sm_api" {
  service = "secretmanager.googleapis.com"
}

resource "google_cloud_run_service" "event_handler" {
  name     = "event-handler"
  location = var.google_region

  template {
    spec {
      containers {
        image = "gcr.io/cloudrun/placeholder"
        env {
          name  = "PROJECT_NAME"
          value = var.google_project_id
        }
      }
      service_account_name = google_service_account.fourkeys.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true

  depends_on = [
    google_project_service.run_api,
  ]

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image
    ]
  }

}

resource "google_cloud_run_domain_mapping" "event_handler" {
  location = var.google_domain_mapping_region
  name     = var.mapped_domain

  metadata {
    namespace = var.google_project_id
  }

  spec {
    route_name = google_cloud_run_service.event_handler.name
  }
}

resource "google_cloud_run_service_iam_binding" "noauth" {
  count    = var.make_event_handler_public ? 1 : 0
  location = var.google_region
  project  = var.google_project_id
  service  = "event-handler"

  role       = "roles/run.invoker"
  members    = ["allUsers"]
  depends_on = [google_cloud_run_service.event_handler]
}

resource "google_secret_manager_secret" "event_handler" {
  secret_id = "event-handler"
  replication {
    user_managed {
      replicas {
        location = var.google_region
      }
    }
  }
  depends_on = [google_project_service.sm_api]
}

resource "random_id" "event_handler_random_value" {
  byte_length = "20"
}

resource "google_secret_manager_secret_version" "event_handler" {
  secret      = google_secret_manager_secret.event_handler.id
  secret_data = random_id.event_handler_random_value.hex
}

resource "google_secret_manager_secret_iam_member" "event_handler" {
  secret_id = google_secret_manager_secret.event_handler.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.fourkeys.email}"
}

module "cloudbuild_for_publishing" {
  source        = "./cloudbuild-trigger"

  name          = "event-handler-build-deploy"
  description   = "cloud build for creating publishing event handle container images"
  project_id    = var.google_project_id
  filename      = "event_handler/cloudbuild.yaml"
  owner         = var.owner
  repository    = var.repository
  branch        = var.cloud_build_branch
  include       = ["event_handler/**"]
  substitutions = {
    _FOURKEYS_GCR_DOMAIN : "${var.google_region}-docker.pkg.dev"
    _FOURKEYS_REGION : var.google_region
  }
}
