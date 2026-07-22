/**
 * Workload Identity module
 *
 * Creates the two GCP service accounts the platform actually needs and
 * binds each to a Kubernetes ServiceAccount via Workload Identity - no
 * service account key files are ever generated or downloaded.
 *
 *   - app SA:  used by the API Pods. Only needs `cloudsql.client` (the
 *              minimum IAM grain GCP offers for Cloud SQL access) and
 *              read access to the specific secrets it's allowed to see.
 *   - eso SA:  used by the External Secrets Operator controller, which is
 *              what actually pulls values from Secret Manager and
 *              materializes them as native Kubernetes Secrets for the app
 *              to mount. Scoped to the same per-secret grants.
 *
 * Every secretAccessor grant below is bound to one named secret, not the
 * project - a compromised Pod can read the one or two secrets it needs and
 * nothing else in Secret Manager.
 */

# --- Application service account -------------------------------------------

resource "google_service_account" "app" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-app-sa"
  display_name = "API service workload identity (${var.name_prefix})"
}

resource "google_project_iam_member" "app_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app.email}"
}

resource "google_secret_manager_secret_iam_member" "app_secret_access" {
  for_each  = toset(var.secret_ids)
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# Lets the Kubernetes ServiceAccount "impersonate" this GCP service account -
# this single binding is what Workload Identity is built on.
resource "google_service_account_iam_member" "app_workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_pool}[${var.app_namespace}/${var.app_k8s_service_account}]"
}

# --- External Secrets Operator service account ------------------------------

resource "google_service_account" "eso" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-eso-sa"
  display_name = "External Secrets Operator workload identity (${var.name_prefix})"
}

resource "google_secret_manager_secret_iam_member" "eso_secret_access" {
  for_each  = toset(var.secret_ids)
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_pool}[${var.eso_namespace}/${var.eso_k8s_service_account}]"
}
