/**
 * Dev environment
 *
 * Wires the four reusable modules together with dev-sized, cost-optimized
 * settings. Security posture is identical to prod - only capacity,
 * availability, and deletion-protection knobs differ. See the module
 * source for what each one actually creates.
 */

# Every API a module below touches, enabled through Terraform itself so a
# brand-new GCP project needs zero manual `gcloud services enable` calls -
# `terraform apply` alone is enough. `disable_on_destroy = false` because
# turning an API off is a project-wide, blast-radius-unbounded action that
# has nothing to do with tearing down this environment's resources.
locals {
  required_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "certificatemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "dns.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Enabling an API returns success well before Google's backend has finished
# propagating that change - resources created immediately afterward (Secret
# Manager secrets, the Service Networking peering connection) intermittently
# fail with "API has not been used before or is disabled" or spurious auth
# errors even though the API genuinely is enabled. This buffer absorbs that
# lag; everything that touches a newly-enabled API depends on it, not on
# google_project_service.apis directly.
resource "time_sleep" "wait_for_apis" {
  create_duration = "60s"

  depends_on = [google_project_service.apis]
}

module "network" {
  source = "../../modules/network"

  project_id    = var.project_id
  region        = var.region
  name_prefix   = var.name_prefix
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr

  depends_on = [time_sleep.wait_for_apis]
}

module "gke" {
  source = "../../modules/gke"

  project_id             = var.project_id
  region                 = var.region
  name_prefix            = var.name_prefix
  network_id             = module.network.network_id
  subnet_id              = module.network.subnet_id
  pods_range_name        = module.network.pods_range_name
  services_range_name    = module.network.services_range_name
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  # Dev is disposable - no deletion protection so the sandbox tears down
  # cleanly with `terraform destroy`.
  deletion_protection = false

  labels = {
    environment = "dev"
    managed_by  = "terraform"
  }
}

module "database" {
  source = "../../modules/database"

  project_id                        = var.project_id
  region                            = var.region
  name_prefix                       = var.name_prefix
  network_id                        = module.network.network_id
  private_service_access_dependency = module.network.private_service_access_dependency

  tier = var.db_tier

  # --- Cost/HA levers: cheapest safe settings for a dev sandbox ---
  availability_type              = "ZONAL" # single zone - no HA failover cost
  point_in_time_recovery_enabled = false   # saves WAL storage cost
  deletion_protection            = false   # dev must be freely destroyable
  disk_size_gb                   = 20

  labels = {
    environment = "dev"
    managed_by  = "terraform"
  }

  depends_on = [time_sleep.wait_for_apis]
}

module "certificate" {
  source = "../../modules/certificate"

  project_id            = var.project_id
  name_prefix           = var.name_prefix
  hostname              = var.hostname
  dns_managed_zone_name = var.dns_managed_zone_name
  certificate_mode      = var.certificate_mode

  depends_on = [time_sleep.wait_for_apis]
}

# ArgoCD gets its own hostname/cert/Gateway, entirely separate from the
# app's - same certificate module, called a second time.
module "argocd_certificate" {
  source = "../../modules/certificate"

  project_id            = var.project_id
  name_prefix           = "${var.name_prefix}-argocd"
  hostname              = var.argocd_hostname
  dns_managed_zone_name = var.dns_managed_zone_name
  certificate_mode      = var.certificate_mode

  depends_on = [time_sleep.wait_for_apis]
}

module "security" {
  source = "../../modules/security"

  project_id  = var.project_id
  name_prefix = var.name_prefix

  # Dev sees far less traffic than prod - a looser threshold avoids
  # throttling normal test/demo usage.
  rate_limit_threshold_count = 200

  depends_on = [time_sleep.wait_for_apis]
}

# Container for a third-party API key. Terraform manages the secret's
# existence and IAM only - the actual value is added out-of-band (e.g.
# `gcloud secrets versions add`) by whoever owns that credential, so it
# never has to pass through git, CI logs, or Terraform state.
resource "google_secret_manager_secret" "third_party_api_key" {
  project   = var.project_id
  secret_id = var.third_party_api_key_secret_id

  replication {
    auto {}
  }

  labels = {
    environment = "dev"
    managed_by  = "terraform"
  }

  depends_on = [time_sleep.wait_for_apis]
}

module "workload_identity" {
  source = "../../modules/workload-identity"

  project_id    = var.project_id
  name_prefix   = var.name_prefix
  workload_pool = module.gke.workload_pool

  app_namespace           = var.app_namespace
  app_k8s_service_account = "api-service"
  eso_namespace           = "external-secrets"
  eso_k8s_service_account = "external-secrets"

  secret_ids = [
    module.database.db_password_secret_id,
    google_secret_manager_secret.third_party_api_key.secret_id,
  ]
}

# External Secrets Operator - the one cluster-wide add-on this platform
# needs beyond what GKE Autopilot ships with. Installed in this same
# `terraform apply` (rather than a separate manual `helm install` step) by
# talking to the cluster module.gke just created; its controller
# ServiceAccount is annotated for Workload Identity at install time, so
# there's no follow-up `kubectl annotate` step either.
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }

  depends_on = [module.gke]
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.eso_chart_version
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = module.workload_identity.eso_service_account_email
  }
}

# ArgoCD - installed the same way as ESO, in this same `apply`. This dev
# cluster's ArgoCD only ever manages dev's own Applications (see
# argocd/dev/), never prod's - each environment/cluster gets its own
# independent instance. Exposed only through its own Gateway + the same
# Cloud Armor policy protecting the app - no separate, unprotected
# LoadBalancer Service.
module "argocd" {
  source = "../../modules/argocd"

  chart_version        = var.argocd_chart_version
  hostname             = var.argocd_hostname
  certificate_map_name = module.argocd_certificate.certificate_map_name
  security_policy_name = module.security.security_policy_name

  depends_on = [module.gke]
}
