provider "google" {
  project = var.project_id
  region  = var.region
}

# Used to mint a short-lived access token for the kubernetes/helm providers
# below - this is the operator's own `gcloud` identity, not a service
# account key file.
data "google_client_config" "default" {}

# Talks to the GKE cluster this same `terraform apply` just created, so
# cluster-wide add-ons (External Secrets Operator) can be installed in the
# same run as the infrastructure they depend on.
provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}
