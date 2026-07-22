variable "namespace" {
  description = "Kubernetes namespace ArgoCD is installed into."
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-helm `argo-cd` chart version. Pinned for reproducibility - check https://github.com/argoproj/argo-helm/releases before bumping."
  type        = string
}

variable "hostname" {
  description = "DNS hostname the ArgoCD Gateway serves, e.g. argocd-dev.tenant.internal. ArgoCD is reachable ONLY through this Gateway - argocd-server itself stays ClusterIP, with no separate public IP of its own."
  type        = string
}

variable "certificate_map_name" {
  description = "Certificate Manager certificate map name (from the certificate module) backing this Gateway's TLS listener."
  type        = string
}

variable "security_policy_name" {
  description = "Cloud Armor security policy name (from the security module) attached to argocd-server via GCPBackendPolicy - the same policy protecting the app, so ArgoCD's admin UI gets the identical WAF/rate-limit coverage, not a weaker exception."
  type        = string
}

variable "gateway_class_name" {
  description = "GKE GatewayClass - matches the app's Gateway so ArgoCD is provisioned the same way: a global external HTTPS Application Load Balancer, not a raw L4 LoadBalancer Service."
  type        = string
  default     = "gke-l7-global-external-managed"
}
