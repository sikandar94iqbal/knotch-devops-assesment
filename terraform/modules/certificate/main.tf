/**
 * Certificate module
 *
 * Provisions a TLS certificate for the Gateway via Certificate Manager,
 * entirely through Terraform - no console step, no `gcloud` one-liner.
 * Two modes, picked by `var.certificate_mode`:
 *
 *   - "managed" (real deployments): a Google-managed, DNS-validated cert.
 *     DNS-authorized managed certs need one proof-of-ownership CNAME
 *     record; if the domain's zone lives in Cloud DNS in this project
 *     (`dns_managed_zone_name` set), that record is created here too, so
 *     the whole chain from `terraform apply` to an issued certificate is
 *     automatic. Otherwise the record to create is exposed as an output.
 *
 *   - "self_signed" (no domain yet): Terraform generates a self-signed
 *     cert for `hostname` with the `tls` provider and uploads it directly
 *     - no DNS validation, no domain ownership needed, so the Gateway
 *     serves real HTTPS immediately. Good for exercising the full ingress
 *     path locally via `curl --resolve`/`/etc/hosts` before a real domain
 *     exists; browsers will show a certificate warning, exactly as
 *     expected for a self-signed cert.
 */

# --- "managed" mode: real, DNS-validated Google-managed certificate --------

resource "google_certificate_manager_dns_authorization" "this" {
  count = var.certificate_mode == "managed" ? 1 : 0

  project = var.project_id
  name    = "${var.name_prefix}-dns-auth"
  domain  = var.hostname
}

# Only created when we actually control the zone - otherwise this record
# has to be added by whoever administers the domain (see the
# dns_authorization_record output).
resource "google_dns_record_set" "dns_authorization_challenge" {
  count = var.certificate_mode == "managed" && var.dns_managed_zone_name != "" ? 1 : 0

  project      = var.project_id
  managed_zone = var.dns_managed_zone_name
  name         = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "managed" {
  count = var.certificate_mode == "managed" ? 1 : 0

  project = var.project_id
  name    = "${var.name_prefix}-cert"

  managed {
    domains            = [var.hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.this[0].id]
  }

  # Certificate issuance is DNS-validated and asynchronous - Terraform
  # returns as soon as the resource is accepted, not once it's ACTIVE.
  # `terraform apply` succeeding does not by itself mean the cert is live;
  # check with `gcloud certificate-manager certificates describe`.
}

# --- "self_signed" mode: no domain required --------------------------------

resource "tls_private_key" "self_signed" {
  count = var.certificate_mode == "self_signed" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count = var.certificate_mode == "self_signed" ? 1 : 0

  private_key_pem       = tls_private_key.self_signed[0].private_key_pem
  validity_period_hours = 24 * 90 # 90 days - re-`apply` to rotate
  early_renewal_hours   = 24 * 7
  dns_names             = [var.hostname]

  subject {
    common_name  = var.hostname
    organization = "Tenant Platform (self-signed, no domain registered)"
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "google_certificate_manager_certificate" "self_signed" {
  count = var.certificate_mode == "self_signed" ? 1 : 0

  project = var.project_id
  name    = "${var.name_prefix}-cert"

  self_managed {
    pem_certificate = tls_self_signed_cert.self_signed[0].cert_pem
    pem_private_key = tls_private_key.self_signed[0].private_key_pem
  }
}

# --- Certificate map: same in both modes -----------------------------------

resource "google_certificate_manager_certificate_map" "this" {
  project = var.project_id
  name    = "${var.name_prefix}-certmap"
}

resource "google_certificate_manager_certificate_map_entry" "this" {
  project  = var.project_id
  name     = "${var.name_prefix}-certmap-entry"
  map      = google_certificate_manager_certificate_map.this.name
  hostname = var.hostname
  certificates = var.certificate_mode == "managed" ? [
    google_certificate_manager_certificate.managed[0].id
    ] : [
    google_certificate_manager_certificate.self_signed[0].id
  ]
}
