output "certificate_map_name" {
  description = "Certificate Manager certificate map name. Feed this into the Helm chart's `gateway.certificateMapName` value."
  value       = google_certificate_manager_certificate_map.this.name
}

output "dns_authorization_record" {
  description = <<-EOT
    The CNAME record Certificate Manager needs to prove domain ownership.
    Already created automatically when `dns_managed_zone_name` is set;
    otherwise, create this record with your DNS provider once before the
    certificate can move to ACTIVE. `null` in "self_signed" mode - there's
    no domain to validate.
  EOT
  value = var.certificate_mode == "managed" ? {
    name = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].name
    type = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].type
    data = google_certificate_manager_dns_authorization.this[0].dns_resource_record[0].data
  } : null
}
