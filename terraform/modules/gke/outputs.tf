output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_id" {
  description = "Fully qualified ID of the GKE cluster, e.g. for `gcloud container clusters get-credentials`."
  value       = google_container_cluster.this.id
}

output "endpoint" {
  description = "Kubernetes API server endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_pool" {
  description = "Workload Identity pool (PROJECT_ID.svc.id.goog), needed when annotating Kubernetes service accounts."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}
