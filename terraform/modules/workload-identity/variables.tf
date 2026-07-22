variable "project_id" {
  description = "GCP project ID the service accounts and IAM bindings are created in."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"tenant-dev\"."
  type        = string
}

variable "workload_pool" {
  description = "GKE Workload Identity pool (PROJECT_ID.svc.id.goog), from the gke module's output."
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace the API workload runs in."
  type        = string
  default     = "default"
}

variable "app_k8s_service_account" {
  description = "Name of the Kubernetes ServiceAccount used by the API Pods (created by the Helm chart)."
  type        = string
  default     = "api-service"
}

variable "eso_namespace" {
  description = "Kubernetes namespace External Secrets Operator is installed into."
  type        = string
  default     = "external-secrets"
}

variable "eso_k8s_service_account" {
  description = "Name of the Kubernetes ServiceAccount used by the External Secrets Operator controller."
  type        = string
  default     = "external-secrets"
}

variable "secret_ids" {
  description = "Secret Manager secret IDs (short names, not full resource paths) that both the app SA and the ESO SA get secretAccessor on - scoped per-secret, never project-wide."
  type        = list(string)
}
