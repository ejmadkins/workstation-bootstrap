
#### Artifact Registry ####

resource "google_artifact_registry_repository" "repository" {
  location      = var.region
  repository_id = var.artifact_registry_name
  format        = "DOCKER"
  
  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count            = 10
    }
  }
  depends_on = [ google_project_service.service ]
}

#### Service Account for Cloud Build ####

resource "google_service_account" "my_workstation_builder_sa" {
  account_id   = "my-workstation-cloudbuild-sa"
  display_name = "My Workstation Builder Service Account"
}

resource "google_project_iam_member" "my_workstation_builder_sa_builder_role" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.my_workstation_builder_sa.email}"
}

#### Cloud Build Trigger ####

resource "google_cloudbuild_trigger" "build_trigger" {
  name     = "weekly-container-build"
  location = var.region

  repository_event_config {
      repository = var.github_repository
      push {
        branch = "${var.github_branch}"
      }
  }

  filename = "image/cloudbuild.yaml"
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.my_workstation_builder_sa.email}"

  substitutions = {
    _IMAGE_NAME = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repository.repository_id}/my-workstation"
  }

  depends_on = [
    google_project_iam_member.my_workstation_builder_sa_builder_role,
  ]
}

#### Cloud Scheduler ####

resource "google_service_account" "scheduler" {
  account_id   = "my-workstation-scheduler-sa"
  display_name = "My Workstation Builder Service Account for Cloud Scheduler to invoke Cloud Build"
}

resource "google_project_iam_member" "scheduler_cloud_build_invoker" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_service_account_iam_binding" "impersonate-build-sa" {
    service_account_id = google_service_account.my_workstation_builder_sa.id
    role               = "roles/iam.serviceAccountUser"
    members = [
        "serviceAccount:${google_service_account.scheduler.email}",
    ]
}

resource "google_cloud_scheduler_job" "weekly_build" {
  name             = "weekly-workstation-container-build"
  description      = "Trigger weekly build of my Cloud Workstation container image"
  schedule         = "0 0 * * 0" # Every Sunday at midnight
  time_zone        = "Etc/UTC"
  attempt_deadline = "320s"
  region           = var.scheduler_region
  http_target {
    http_method = "POST"
    uri         = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/triggers/${google_cloudbuild_trigger.build_trigger.trigger_id}:run"
    body        = base64encode("{\"source\": {\"branchName\": \"${var.github_branch}\"}}")
    headers     = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [
    google_project_iam_member.scheduler_cloud_build_invoker,
  ]
}