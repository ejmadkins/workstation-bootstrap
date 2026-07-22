variable "tf_sa" {
  description = "Service Account for Terraform - note you must have Service Account Token Creator IAM role for your own account"
  type        = string
}

variable "tf_project" {
  description = "GCP project where Terraform state is stored"
  type        = string
}

variable "project_id" {
  description = "The Google Cloud project ID for your Cloud Workstation."
  type        = string
}

variable "github_repository" {
  description = "The URI of the linked GitHub repository in Google Cloud Build."
  type        = string
}

variable "github_branch" {
  description = "The branch to use for the build trigger."
  type        = string
  default     = "main"
}

variable "workstation_user" {
  description = "The organisation user that will be granted access to the workstation."
  type        = string
}

variable "region" {
  description = "The Google Cloud region to deploy resources in."
  type        = string
  default     = "europe-west2"
}

variable "scheduler_region" {
  description = "The Google Cloud region to run Cloud Scheduler from."
  type        = string
  default     = "europe-west2"
}

variable "artifact_registry_name" {
  description = "The name of the Artifact Registry repository."
  type        = string
  default     = "my-workstation-image"
}

variable "machine_type" {
  description = "The machine type for the Cloud Workstation."
  type        = string
  default     = "t2d-standard-4"
}

variable "idle_timeout" {
  description = "The idle timeout in seconds after which the workstation will automatically stop."
  type        = number
  default     = 21600
}

variable "workstation_disk_size" {
  description = "The size of the persistent disk attached to the workstation."
  type        = number
  default     = 100
}
