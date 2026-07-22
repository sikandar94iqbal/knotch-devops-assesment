/**
 * GKE module
 *
 * A private GKE Autopilot cluster. Autopilot removes node management
 * entirely (Google patches and scales nodes; we're billed per-Pod request,
 * not per-VM), and it hard-enforces the security posture this platform
 * needs by default: Shielded GKE Nodes, Workload Identity, and a locked-down
 * Pod security posture that rejects privileged containers outright. That
 * default-secure posture is exactly why Autopilot was chosen over Standard
 * for this assessment - there's no node-level hardening to get wrong.
 *
 * `enable_private_nodes = true` means every node gets only an internal IP;
 * outbound access goes through the Cloud NAT set up in the network module.
 * The control plane keeps a public endpoint (gated by
 * `master_authorized_networks`) purely so ArgoCD/kubectl/CI can reach the
 * Kubernetes API without a bastion host or VPN for this assessment - the
 * data plane (nodes, Pods) never has a public IP either way.
 */

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = "${var.name_prefix}-gke"
  location = var.region # regional cluster: control plane replicas span 3 zones

  enable_autopilot    = true
  deletion_protection = var.deletion_protection

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  # Lets Pods authenticate to GCP APIs as GCP service accounts via OIDC
  # federation - no service account key files anywhere in the cluster.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Installs the GKE Gateway controller + GatewayClasses (gke-l7-*) so the
  # Helm chart's Gateway/HTTPRoute objects actually provision a load
  # balancer. Without this the CRDs exist (they ship with Kubernetes) but
  # nothing reconciles them.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  resource_labels = var.labels

  # Autopilot manages node pools, node OS, and Shielded VM settings itself -
  # there is intentionally no node_pool block here.
}
