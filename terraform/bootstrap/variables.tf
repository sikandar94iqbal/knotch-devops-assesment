variable "project_id" {
  description = "GCP project ID to create the Terraform state bucket in."
  type        = string
}

variable "region" {
  description = "GCP region for the provider default (not the bucket itself, which is multi-region for durability)."
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Name of the GCS bucket that will hold every environment's Terraform state. Must be globally unique across all of GCP."
  type        = string
}
