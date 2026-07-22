terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Deliberately no "backend" block: this stack creates the GCS bucket that
  # the dev/prod environments use AS their backend, so it can't use that
  # same bucket itself (or any GCS backend) without a chicken-and-egg
  # problem. Its own state stays local (a single `terraform.tfstate` file
  # in this directory) - low risk, since the only resource it manages is
  # one bucket. If that local state file is ever lost, the bucket itself
  # is untouched in GCP; re-attach with:
  #   terraform import google_storage_bucket.tf_state <project_id>/<bucket_name>
}
