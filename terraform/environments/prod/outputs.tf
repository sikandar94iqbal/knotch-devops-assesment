output "cluster_name" {
  description = "Name of the GKE cluster. Use with `gcloud container clusters get-credentials`."
  value       = module.gke.cluster_name
}

output "database_private_ip" {
  description = "Private IP of the Cloud SQL instance - only reachable from inside the VPC. Feed this into the Helm chart's DB host value."
  value       = module.database.private_ip_address
}

output "database_name" {
  description = "Application database name."
  value       = module.database.database_name
}

output "database_user" {
  description = "Application database user."
  value       = module.database.database_user
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID holding the DB password (name only, not the value)."
  value       = module.database.db_password_secret_id
}

output "app_service_account_email" {
  description = "GCP service account email for the API workload - annotate the Kubernetes ServiceAccount with this via Helm values."
  value       = module.workload_identity.app_service_account_email
}

output "eso_service_account_email" {
  description = "GCP service account email for External Secrets Operator - annotate its Kubernetes ServiceAccount with this at install time."
  value       = module.workload_identity.eso_service_account_email
}

output "certificate_map_name" {
  description = "Certificate Manager certificate map name - feed into the Helm chart's `gateway.certificateMapName` value."
  value       = module.certificate.certificate_map_name
}

output "dns_authorization_record" {
  description = "DNS CNAME record proving ownership of `var.hostname`. Already created if dns_managed_zone_name was set; otherwise create it with your DNS provider before the certificate can go ACTIVE. `null` in self_signed mode."
  value       = module.certificate.dns_authorization_record
}

output "security_policy_name" {
  description = "Cloud Armor security policy name - feed into the Helm chart's `cloudArmor.securityPolicyName` value."
  value       = module.security.security_policy_name
}

output "gateway_ip_hint" {
  description = "Reminder: the app Gateway's external IP is only known after `kubectl apply`/ArgoCD provisions it - run `kubectl get gateway <name> -n <namespace>` post-deploy, it's not a Terraform output."
  value       = "Run: kubectl get gateway -n ${var.app_namespace}"
}

output "argocd_certificate_map_name" {
  description = "Certificate Manager certificate map name for ArgoCD's Gateway - already wired into the argocd module, surfaced here only for `gcloud certificate-manager` lookups."
  value       = module.argocd_certificate.certificate_map_name
}

output "argocd_url" {
  description = "ArgoCD URL - deterministic as soon as `apply` finishes, since it's just the hostname you set, not a runtime-assigned IP. Reachable only through this Gateway + the same Cloud Armor policy protecting the app; argocd-server has no public IP of its own."
  value       = "https://${var.argocd_hostname}/"
}

output "argocd_gateway_ip_hint" {
  description = "ArgoCD's Gateway gets its own external IP, separate from the app's - map var.argocd_hostname to this IP (DNS or curl --resolve) the same way you do for the app."
  value       = "Run: kubectl get gateway argocd-gateway -n ${module.argocd.namespace}"
}

output "argocd_admin_password_hint" {
  description = "ArgoCD auto-generates an initial admin password at install time - it's never a Terraform output (never touches state). Fetch it with this command."
  value       = "Run: kubectl -n ${module.argocd.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
