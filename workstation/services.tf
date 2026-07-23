##### Enable required APIs #####

resource "google_project_service" "service" {
  for_each = toset([
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "osconfig.googleapis.com",
    "secretmanager.googleapis.com",
    "workstations.googleapis.com",
    "cloudscheduler.googleapis.com",
    # note, this is a requirement for OS config, it uses this service to store patch compliance data
    "containeranalysis.googleapis.com",
  ])
  service = each.value
  # note compute.googleapis.com can't seem to destroy and generates errors otherwise
  # but as we are destroying the project too it's a moot point
  disable_on_destroy = false
}
