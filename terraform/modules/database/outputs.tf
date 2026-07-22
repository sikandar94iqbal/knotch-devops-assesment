output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Cloud SQL connection name (project:region:instance), useful if the Cloud SQL Auth Proxy is ever added as a sidecar."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the Cloud SQL instance. Not a secret - this is only reachable from inside the peered VPC. Delivered to the app via a plain Helm value / ConfigMap, not Secret Manager."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  description = "Name of the application database."
  value       = google_sql_database.app.name
}

output "database_user" {
  description = "Name of the application database user."
  value       = google_sql_user.app.name
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID holding the DB password. This is just a name, not the secret value - safe to pass into the workload-identity module and the ExternalSecret manifest."
  value       = google_secret_manager_secret.db_password.secret_id
}
