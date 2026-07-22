variable "project_id" {
  description = "GCP project ID the certificate resources are created in."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"tenant-dev\"."
  type        = string
}

variable "hostname" {
  description = "DNS hostname the Gateway serves and the managed certificate covers, e.g. api-dev.example.com."
  type        = string
}

variable "dns_managed_zone_name" {
  description = <<-EOT
    Name of an existing Cloud DNS public managed zone (in this project) that
    is authoritative for `hostname`. When set, this module creates the DNS
    authorization CNAME record automatically, so the certificate finishes
    provisioning without a manual DNS step. Leave blank if the domain is
    managed outside Cloud DNS (e.g. an external registrar) - the required
    CNAME record is then surfaced via the `dns_authorization_record` output
    for you to create by hand, once, out-of-band. Ignored when
    `certificate_mode = "self_signed"`.
  EOT
  type        = string
  default     = ""
}

variable "certificate_mode" {
  description = <<-EOT
    "managed" (default): a real, Google-managed, DNS-validated certificate
    for `hostname` - use this once you own a real domain.
    "self_signed": Terraform generates a self-signed cert for `hostname` and
    uploads it to Certificate Manager directly - no domain or DNS validation
    needed. Lets the Gateway serve real HTTPS immediately for local
    testing (`curl --resolve`/`/etc/hosts`); swap back to "managed" and
    re-apply once a real domain is available - the certificate map entry
    just starts pointing at a different certificate, nothing else changes.
  EOT
  type        = string
  default     = "managed"

  validation {
    condition     = contains(["managed", "self_signed"], var.certificate_mode)
    error_message = "certificate_mode must be \"managed\" or \"self_signed\"."
  }
}
