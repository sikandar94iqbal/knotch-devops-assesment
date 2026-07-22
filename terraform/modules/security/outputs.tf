output "security_policy_name" {
  description = "Cloud Armor security policy name. Feed into the Helm chart's `cloudArmor.securityPolicyName` value, referenced by the GCPBackendPolicy."
  value       = google_compute_security_policy.this.name
}
