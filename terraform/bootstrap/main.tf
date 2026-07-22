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

  # Belt-and-suspenders on top of uniform_bucket_level_access - don't rely
  # on org policy inheritance alone to keep this bucket off the public
  # internet, since it holds every environment's Terraform state.
  public_access_prevention = "enforced"

  # State LOCKING itself needs no separate config: Terraform's "gcs"
  # backend always uses this bucket's atomic, generation-conditional
  # writes to lock state during an apply - unlike some other backends,
  # there's no lock table/flag to turn on. Versioning below is what makes
  # every past state readable/recoverable, which is the "trace" half of
  # the ask - locking and history are two different mechanisms, both
  # already covered by a plain GCS backend.
  versioning {
    enabled = true
  }

  # Keeps the audit trail bounded: old state versions stay recoverable for
  # 30 days, then age out automatically instead of growing forever. The
  # live (current) state version is never touched by this rule - it only
  # ever acts on noncurrent (superseded) versions.
  lifecycle_rule {
    condition {
      num_newer_versions         = 3
      days_since_noncurrent_time = var.noncurrent_version_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # This bucket holds every environment's Terraform state - losing it is
  # far worse than the inconvenience of an explicit `terraform destroy`
  # override if it's ever genuinely meant to go away.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.storage]
}
