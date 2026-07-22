output "namespace" {
  description = "Namespace ArgoCD is installed into."
  value       = kubernetes_namespace.this.metadata[0].name
}
