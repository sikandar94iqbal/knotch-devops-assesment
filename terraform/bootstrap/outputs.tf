output "bucket_name" {
  description = "Paste this into the `bucket` field of the backend \"gcs\" block in terraform/environments/{dev,prod}/versions.tf."
  value       = google_storage_bucket.tf_state.name
}
