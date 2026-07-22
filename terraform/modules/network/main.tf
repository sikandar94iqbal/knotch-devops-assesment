/**
 * Network module
 *
 * Builds the private networking foundation the whole platform sits on:
 *   - A custom-mode VPC (no default routes/firewalls, no "default" network reuse)
 *   - One VPC-native subnet per environment, with secondary ranges for GKE
 *     Autopilot Pods and Services
 *   - Private Service Access (VPC peering) so Cloud SQL gets a private IP
 *     that is only reachable from inside this VPC
 *   - Cloud Router + Cloud NAT so private GKE nodes can still reach the
 *     internet (image pulls, package installs) without a public IP
 *
 * Nothing here has a public IP. The only inbound path into the VPC is the
 * external HTTPS load balancer provisioned later by the GKE Gateway API,
 * which talks to Pods via Google Front End health-checked backends, not a
 * raw VPC ingress rule.
 */

# Custom-mode VPC: we define every subnet and firewall rule ourselves rather
# than inheriting GCP's permissive "default" network.
resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# The subnet GKE Autopilot nodes, Pods, and Services live in.
# `private_ip_google_access` lets nodes reach Google APIs (Secret Manager,
# Cloud SQL Admin, etc.) over Google's private backbone instead of the
# public internet.
resource "google_compute_subnetwork" "gke" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-gke-subnet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.name_prefix}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${var.name_prefix}-services"
    ip_cidr_range = var.services_cidr
  }

  # Flow logs give us an audit trail of traffic in/out of the subnet -
  # cheap insurance for a "production security practices" requirement.
  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Reserved IP range handed to Google, used exclusively for the VPC peering
# that backs Private Service Access. This is what lets Cloud SQL hand out a
# private IP address inside our VPC's address space.
resource "google_compute_global_address" "private_service_access" {
  project       = var.project_id
  name          = "${var.name_prefix}-psa-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_service_access_cidr_prefix_length
  network       = google_compute_network.this.id
}

# The actual VPC peering connection to Google's service producer network.
# Every private-IP Cloud SQL instance in this project rides on this peering.
resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]
}

# Cloud Router is required by Cloud NAT to learn routes.
resource "google_compute_router" "nat" {
  project = var.project_id
  name    = "${var.name_prefix}-nat-router"
  region  = var.region
  network = google_compute_network.this.id
}

# Cloud NAT gives GKE Autopilot's private nodes outbound internet access
# (e.g. pulling container images) without ever assigning them a public IP.
resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Google Front End (GFE) health checkers and load balancer proxies live in
# these two well-known ranges. The Gateway API's managed load balancer needs
# to reach Pod backends through them, so we allow ingress from just these
# ranges rather than opening the subnet broadly.
resource "google_compute_firewall" "allow_lb_health_checks" {
  project       = var.project_id
  name          = "${var.name_prefix}-allow-gfe-health-checks"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
  }
}
