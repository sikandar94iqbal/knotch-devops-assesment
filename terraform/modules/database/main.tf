/**
 * Database module
 *
 * Cloud SQL for PostgreSQL, reachable only via its private IP on the peered
 * VPC (`ipv4_enabled = false` - there is no public IP to even lock down).
 * The generated password never leaves Terraform state in plaintext output;
 * it's written straight to Secret Manager and the application reads it at
 * runtime via External Secrets Operator + Workload Identity.
 */

# Generated once, stored only in Terraform state (which lives encrypted in
# the GCS backend) and in Secret Manager - never printed to a CI log or a
# terraform output.
resource "random_password" "db_password" {
  length  = 32
  special = true
  # Cloud SQL rejects some punctuation in passwords; keep it to a safe set.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = "${var.name_prefix}-postgres"
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  # Cloud SQL's private-peering setup requires the peering to exist first;
  # without this the instance creation races the VPC peering and can fail.
  depends_on = [var.private_service_access_dependency]

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_size         = var.disk_size_gb
    disk_autoresize   = true
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false # No public IP - private-only by construction, not firewall rule.
      private_network = var.network_id
      # Rejects any unencrypted connection; doesn't require a client
      # certificate (the app authenticates with a DB password, not mTLS).
      ssl_mode = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.point_in_time_recovery_enabled ? 7 : null
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 4 # 04:00 - low traffic window
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
    }

    user_labels = var.labels
  }

  lifecycle {
    prevent_destroy = false # Terraform-level protection comes from var.deletion_protection above.
  }
}

resource "google_sql_database" "app" {
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "app" {
  project  = var.project_id
  name     = var.database_user
  instance = google_sql_database_instance.this.name
  password = random_password.db_password.result
}

# The secret container. Access is granted (in the workload-identity module)
# to exactly this secret, not to Secret Manager project-wide.
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-db-password"

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}
