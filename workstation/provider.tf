provider "google" {
 alias = "impersonation"
}

data "google_service_account_access_token" "default" {
 provider               	= google.impersonation
 target_service_account 	= var.tf_sa
 scopes                 	= ["cloud-platform"]
 # note that this needs to be longer than the time to provision the stack
 lifetime               	= "3600s"
}

provider "google" {
  project         = var.project_id
  region          = var.region
  access_token	  = data.google_service_account_access_token.default.access_token
  request_timeout = "60s"
}

provider "google-beta" {
  project         = var.project_id
  region          = var.region
  access_token	  = data.google_service_account_access_token.default.access_token
  request_timeout = "60s"
}