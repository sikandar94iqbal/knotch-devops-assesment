variable "project_id" {
  description = "GCP project ID the cluster is created in."
  type        = string
}

variable "region" {
  description = "GCP region for the (regional) Autopilot cluster."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"tenant-dev\"."
  type        = string
}

variable "network_id" {
  description = "Self link of the VPC to attach the cluster to (from the network module)."
  type        = string
}

variable "subnet_id" {
  description = "Self link of the subnet to attach the cluster to (from the network module)."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary IP range for Pods (from the network module)."
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary IP range for Services (from the network module)."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "RFC 1918 /28 CIDR for the GKE control plane's private endpoint. Must not overlap with any other range in the VPC."
  type        = string
}

variable "release_channel" {
  description = "GKE release channel. REGULAR balances new features against stability; Autopilot requires a channel."
  type        = string
  default     = "REGULAR"
}

variable "master_authorized_networks" {
  description = <<-EOT
    CIDR ranges allowed to reach the GKE control plane's public endpoint
    (nodes stay fully private regardless of this setting - this only
    controls who can call the Kubernetes API, e.g. `kubectl`/ArgoCD/CI).
    Defaults to open for assessment convenience; restrict to your office/CI
    egress ranges for a real deployment.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "all (dev-convenience - restrict for real prod use)"
    }
  ]
}

variable "deletion_protection" {
  description = "Terraform/API-level guard against accidental cluster deletion. On for prod, off for dev."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Resource labels applied to the cluster."
  type        = map(string)
  default     = {}
}
