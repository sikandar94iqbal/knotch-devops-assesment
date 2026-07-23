variable "project_id" {
  description = "GCP project ID the database is created in."
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud SQL instance."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"tenant-dev\"."
  type        = string
}

variable "network_id" {
  description = "Self link of the VPC to peer Cloud SQL's private IP into. Must already have Private Service Access configured (see the network module)."
  type        = string
}

variable "private_service_access_dependency" {
  description = "Pass through the network module's private_service_access output so Terraform waits for the VPC peering to exist before creating an instance that needs it."
  type        = any
}

variable "database_version" {
  description = "Cloud SQL Postgres engine version."
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "Machine tier for the Cloud SQL instance, e.g. db-f1-micro (dev) or db-custom-2-7680 (prod)."
  type        = string
}

variable "availability_type" {
  description = "ZONAL (dev, cheaper) or REGIONAL (prod, HA with automatic failover)."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Provisioned disk size in GB. Autoresize is enabled so this is just the starting point."
  type        = number
  default     = 30
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound on automatic disk growth (0 = unlimited, the Cloud SQL default). Purely a cost/safety cap - a runaway disk-filling issue hits this limit and starts failing loudly instead of silently autoresizing (and billing) forever. Comfortable headroom over disk_size_gb for either environment's current sizing."
  type        = number
  default     = 100
}

variable "backup_enabled" {
  description = "Whether automated daily backups are enabled."
  type        = bool
  default     = true
}

variable "point_in_time_recovery_enabled" {
  description = "Whether WAL-based point-in-time recovery is enabled. Costs extra storage - on for prod, off for dev."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Terraform/API-level guard against accidental instance deletion. On for prod, off for dev so the sandbox is easy to tear down."
  type        = bool
  default     = false
}

variable "database_name" {
  description = "Name of the application database created inside the instance."
  type        = string
  default     = "appdb"
}

variable "database_user" {
  description = "Name of the application database user."
  type        = string
  default     = "appuser"
}

variable "labels" {
  description = "Labels applied to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
