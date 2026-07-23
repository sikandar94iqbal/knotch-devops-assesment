/**
 * Prod environment
 *
 * Same modules, same security posture as dev - only capacity, HA, backup,
 * and deletion-protection settings differ. That symmetry is the point: an
 * engineer reading this file next to dev/main.tf should see identical
 * architecture and only the cost/reliability knobs changed.
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
    # Needed by module.workload_identity's google_project_iam_member (grants
    # the app SA project-level roles/cloudsql.client) - that resource type
    # reads/writes project IAM policy through this API, not IAM's own API.
    "cloudresourcemanager.googleapis.com",
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

  # Prod protects itself from an accidental `terraform destroy`.
  deletion_protection = true

  labels = {
    environment = "prod"
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

  # --- HA/durability levers: this is the only real difference from dev ---
  availability_type              = "REGIONAL" # synchronous standby + automatic failover
  point_in_time_recovery_enabled = true       # recover to any point in the retention window
  deletion_protection            = true       # a stray `terraform destroy` can't take prod down
  disk_size_gb                   = 50

  labels = {
    environment = "prod"
    managed_by  = "terraform"
  }

  depends_on = [time_sleep.wait_for_apis]
}

resource "google_secret_manager_secret" "third_party_api_key" {
  project   = var.project_id
  secret_id = var.third_party_api_key_secret_id

  replication {
    auto {}
  }

  labels = {
    environment = "prod"
    managed_by  = "terraform"
  }

  depends_on = [time_sleep.wait_for_apis]

  # Prod-only guard: deleting this secret loses the third-party credential
  # with no recovery path. teardown-prod.sh flips this to false (alongside
  # the deletion_protection flags below) before a real teardown.
  lifecycle {
    prevent_destroy = true
  }
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

  # Prod sees real traffic - a tighter threshold catches abusive clients
  # sooner than dev's looser one.
  rate_limit_threshold_count = 100

  depends_on = [time_sleep.wait_for_apis]
}

# External Secrets Operator - installed in this same `terraform apply` by
# talking to the cluster module.gke just created; its controller
# ServiceAccount is annotated for Workload Identity at install time.
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

# ArgoCD - installed the same way as ESO, in this same `apply`. This prod
# cluster's ArgoCD only ever manages prod's own Applications (see
# argocd/prod/), entirely independent of dev's ArgoCD instance. Exposed
# only through its own Gateway + the same Cloud Armor policy protecting
# the app - no separate, unprotected LoadBalancer Service.
module "argocd" {
  source = "../../modules/argocd"

  chart_version        = var.argocd_chart_version
  hostname             = var.argocd_hostname
  certificate_map_name = module.argocd_certificate.certificate_map_name
  security_policy_name = module.security.security_policy_name

  depends_on = [module.gke]
}
