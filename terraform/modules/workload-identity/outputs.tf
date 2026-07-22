output "app_service_account_email" {
  description = "Email of the app's GCP service account. Goes into the `iam.gke.io/gcp-service-account` annotation on the Kubernetes ServiceAccount (set via Helm values)."
  value       = google_service_account.app.email
}

output "eso_service_account_email" {
  description = "Email of the External Secrets Operator's GCP service account. Goes into the `iam.gke.io/gcp-service-account` annotation on ESO's Kubernetes ServiceAccount at install time."
  value       = google_service_account.eso.email
}
