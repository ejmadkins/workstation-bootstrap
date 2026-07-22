
#### Networking for the Cloud Workstation ####

resource "google_compute_network" "workstation_vpc" {
  name                    = "workstation-vpc"
  auto_create_subnetworks = false
  depends_on = [ google_project_service.service ]
}

resource "google_compute_subnetwork" "workstation_subnet" {
  name          = "workstation-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.workstation_vpc.self_link
  region        = var.region
}

resource "google_compute_router" "router" {
  name    = "workstation-router"
  network = google_compute_network.workstation_vpc.id
  region  = google_compute_subnetwork.workstation_subnet.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "workstation-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  nat_ip_allocate_option             = "AUTO_ONLY"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

#### Service account for the workstation ####

resource "google_service_account" "my_workstation_sa" {
  account_id   = "my-workstation-sa"
  display_name = "My Workstation Service Account"
}

# required to allow pulling of the custom image
resource "google_project_iam_member" "my_workstation_sa_artifactregistry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.my_workstation_sa.email}"
}

resource "google_project_iam_member" "my_workstation_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.my_workstation_sa.email}"
}

resource "google_project_iam_member" "my_workstation_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.my_workstation_sa.email}"
}

# required to allow the user to SSH access
resource "google_service_account_iam_member" "my_workstation_sa_service_account_user" {
  service_account_id = google_service_account.my_workstation_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "user:${var.workstation_user}"
}

#### Cloud Workstation #####

resource "google_workstations_workstation_cluster" "default" {
  provider = google-beta
  workstation_cluster_id = "my-workstation-cluster"
  network                = google_compute_network.workstation_vpc.id
  subnetwork             = google_compute_subnetwork.workstation_subnet.id
  location               = var.region
}

resource "google_workstations_workstation_config" "default" {
  provider = google-beta
  workstation_config_id  = "my-workstation-config"
  workstation_cluster_id = google_workstations_workstation_cluster.default.workstation_cluster_id
  location               = var.region

  host {
    gce_instance {
      machine_type = var.machine_type
      boot_disk_size_gb = 50
      disable_public_ip_addresses = true
      shielded_instance_config {
        enable_secure_boot          = true
        enable_vtpm                 = true
        enable_integrity_monitoring = true
      }
      service_account = google_service_account.my_workstation_sa.email
    }
  }

  persistent_directories {
    mount_path = "/home"
    gce_pd {
      size_gb        = var.workstation_disk_size
      fs_type        = "ext4"
      disk_type      = "pd-balanced"
      reclaim_policy = "RETAIN"
    }
  }

  idle_timeout = "${var.idle_timeout}s"

  container {
    image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repository.repository_id}/my-workstation"
  }
}

resource "google_workstations_workstation" "default" {
  provider = google-beta
  workstation_id         = "my-workstation"
  display_name           = "My Workstation" 
  workstation_config_id  = google_workstations_workstation_config.default.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.default.workstation_cluster_id
  location               = var.region
}

resource "google_workstations_workstation_iam_member" "member" {
  provider = google-beta
  workstation_cluster_id = google_workstations_workstation.default.workstation_cluster_id
  workstation_config_id = google_workstations_workstation.default.workstation_config_id
  workstation_id = google_workstations_workstation.default.workstation_id
  role = "roles/workstations.user"
  member = "user:${var.workstation_user}"
}