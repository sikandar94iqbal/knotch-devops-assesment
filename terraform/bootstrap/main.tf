/**
 * Bootstrap stack
 *
 * The one piece of infrastructure that can't be created by the
 * dev/prod environments themselves: the GCS bucket they use as their own
 * Terraform state backend. A `backend "gcs"` block requires the bucket to
 * already exist before `terraform init` can even run, so this has to be a
 * separate, earlier `apply` - everything else in this repo (APIs, VPC,
 * GKE, Cloud SQL, Cloud Armor, ArgoCD, ESO, ...) is created by the
 * dev/prod environments' own `terraform apply`, no manual step needed.
 *
 * Run this once per GCP project, before touching terraform/environments/*.
 */

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "tf_state" {
  project  = var.project_id
  name     = var.bucket_name
  location = "US" # multi-region: state durability matters more than latency for a file this small

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # This bucket holds every environment's Terraform state - losing it is
  # far worse than the inconvenience of an explicit `terraform destroy`
  # override if it's ever genuinely meant to go away.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.storage]
}
