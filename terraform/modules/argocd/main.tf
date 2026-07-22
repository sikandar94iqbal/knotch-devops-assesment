/**
 * ArgoCD module
 *
 * Installs ArgoCD into the cluster via the upstream argo-helm chart, in the
 * same `terraform apply` that creates the cluster - the same pattern
 * already used for External Secrets Operator.
 *
 * argocd-server stays ClusterIP - it has NO public IP of its own. It's
 * reachable only through a dedicated Gateway (same GKE Gateway API +
 * Cloud Armor pattern as the app's own Gateway, just a separate Gateway/
 * hostname/IP so the two stay cleanly separated). Every public-facing
 * endpoint in this platform - the app and ArgoCD alike - goes through a
 * GLB with Cloud Armor in front of it; nothing bypasses that path with its
 * own raw LoadBalancer Service.
 *
 * Each environment (dev, prod) gets its own, independent ArgoCD instance,
 * because each environment is its own GKE cluster - this is NOT a single
 * shared ArgoCD managing both. That keeps a prod ArgoCD outage/misconfig
 * from having any way to touch dev, and vice versa.
 */

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace.this.metadata[0].name

  set {
    # No LoadBalancer Service here - TLS termination and public exposure
    # both happen at the Gateway below, not at argocd-server itself.
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    # argocd-server serves plain HTTP; the Gateway is the one and only
    # place TLS is terminated, same as the app.
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }
}

# Gateway + HTTPRoute + GCPBackendPolicy for argocd-server. These are raw
# Kubernetes custom resources, not part of the upstream argo-cd chart, so
# they're bundled as a tiny local Helm chart (./chart) and installed via
# Terraform's helm provider - the same mechanism already proven to work for
# ArgoCD/ESO on a from-scratch `apply`, unlike `kubernetes_manifest`, which
# needs a live cluster connection at *plan* time and can't be used when the
# cluster is created in this same apply.
resource "helm_release" "argocd_gateway" {
  name      = "argocd-gateway"
  chart     = "${path.module}/chart"
  namespace = kubernetes_namespace.this.metadata[0].name

  set {
    name  = "hostname"
    value = var.hostname
  }

  set {
    name  = "certificateMapName"
    value = var.certificate_map_name
  }

  set {
    name  = "securityPolicyName"
    value = var.security_policy_name
  }

  set {
    name  = "gatewayClassName"
    value = var.gateway_class_name
  }

  depends_on = [helm_release.argocd]
}
