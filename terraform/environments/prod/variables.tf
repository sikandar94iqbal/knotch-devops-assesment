variable "project_id" {
  description = "GCP project ID to deploy the prod environment into."
  type        = string
}

variable "region" {
  description = "GCP region for all regional resources."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix applied to every resource name in this environment."
  type        = string
  default     = "tenant-prod"
}

variable "subnet_cidr" {
  description = "Primary CIDR range for the GKE subnet."
  type        = string
  default     = "10.11.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE Pods."
  type        = string
  default     = "10.21.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE Services."
  type        = string
  default     = "10.31.0.0/20"
}

variable "master_ipv4_cidr_block" {
  description = "RFC 1918 /28 for the GKE control plane's private endpoint."
  type        = string
  default     = "10.41.0.0/28"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. db-custom-2-7680 (2 vCPU / 7.5GB) is right-sized for a small prod tenant, not oversized for a demo."
  type        = string
  default     = "db-custom-2-7680"
}

variable "app_namespace" {
  description = "Kubernetes namespace the API workload is deployed into."
  type        = string
  default     = "tenant-prod"
}

variable "third_party_api_key_secret_id" {
  description = "Secret Manager secret ID that will hold a third-party API key. Terraform only creates the empty secret container; the value is added out-of-band by an operator, never through Terraform or git."
  type        = string
  default     = "tenant-prod-third-party-api-key"
}

variable "hostname" {
  description = "DNS hostname the Gateway serves and the managed certificate covers, e.g. api.example.com."
  type        = string
}

variable "dns_managed_zone_name" {
  description = "Name of an existing Cloud DNS public managed zone (in this project) authoritative for `hostname`. Leave blank if the domain is managed outside Cloud DNS - see the certificate module's `dns_authorization_record` output for the manual step."
  type        = string
  default     = ""
}

variable "certificate_mode" {
  description = "\"managed\": real, DNS-validated Google-managed cert (needs a real domain). \"self_signed\": Terraform-generated self-signed cert - no domain required. See the certificate module for details."
  type        = string
  default     = "managed"
}

variable "eso_chart_version" {
  description = "External Secrets Operator Helm chart version. Pinned for reproducibility - check https://github.com/external-secrets/external-secrets/releases before bumping."
  type        = string
  default     = "0.10.7"
}

variable "argocd_chart_version" {
  description = "argo-helm `argo-cd` chart version. Pinned for reproducibility - check https://github.com/argoproj/argo-helm/releases before bumping."
  type        = string
  default     = "7.7.11"
}

variable "argocd_hostname" {
  description = "DNS hostname ArgoCD's own Gateway serves - separate from the app's hostname, but exposed the same way (Gateway + Cloud Armor), never its own raw LoadBalancer."
  type        = string
}
