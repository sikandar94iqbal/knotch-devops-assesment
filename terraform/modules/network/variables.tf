variable "project_id" {
  description = "GCP project ID the network resources are created in."
  type        = string
}

variable "region" {
  description = "GCP region for the subnet, Cloud Router, and Cloud NAT."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"tenant-dev\"."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary CIDR range for the GKE subnet (node IPs)."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE Pod IPs (VPC-native cluster)."
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE Service (ClusterIP) IPs."
  type        = string
}

variable "private_service_access_cidr_prefix_length" {
  description = "Prefix length of the reserved range handed to Google's Private Service Access peering for Cloud SQL. /16 comfortably covers Cloud SQL plus future peered services."
  type        = number
  default     = 16
}

variable "backend_ports" {
  description = "TCP ports the GFE health-check/LB firewall rule allows through - only the ports backend Services actually listen on, not every port."
  type        = list(string)
  default     = ["8080"]
}
