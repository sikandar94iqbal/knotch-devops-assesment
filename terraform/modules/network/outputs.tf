output "network_id" {
  description = "Self link / ID of the VPC. Consumed by the GKE and database modules."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "Self link / ID of the GKE subnet."
  value       = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  description = "Name of the GKE subnet."
  value       = google_compute_subnetwork.gke.name
}

output "pods_range_name" {
  description = "Name of the secondary IP range used for GKE Pods."
  value       = google_compute_subnetwork.gke.secondary_ip_range[0].range_name
}

output "services_range_name" {
  description = "Name of the secondary IP range used for GKE Services."
  value       = google_compute_subnetwork.gke.secondary_ip_range[1].range_name
}

output "private_service_access_dependency" {
  description = "The Private Service Access connection resource. Downstream modules (database) should depend_on this so Cloud SQL isn't created before the peering exists."
  value       = google_service_networking_connection.private_service_access
}
