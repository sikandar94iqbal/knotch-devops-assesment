# The PROD GCP project - must be a DIFFERENT project ID than dev's
# (terraform/environments/dev/terraform.tfvars). See the same note in
# dev/terraform.tfvars: separate projects are what actually isolate dev
# from prod, not just separate name prefixes within one shared project.
project_id = "knotch-prod"
region     = "us-central1"

# No real domain registered yet: certificate_mode = "self_signed" makes
# Terraform generate and upload a self-signed cert for these hostnames, so
# both Gateways serve real HTTPS without any DNS validation. Neither
# hostname needs to resolve anywhere public - map each to its Gateway's IP
# in /etc/hosts (or use `curl --resolve`) to test, same as dev.
#
# Once you have a real domain: change these to real hostnames, flip
# certificate_mode to "managed", and re-`apply` - the cert map entries
# just start pointing at real, DNS-validated certificates instead.
hostname         = "api-prod.tenant.internal"
argocd_hostname  = "argocd-prod.tenant.internal"
certificate_mode = "self_signed"

# If this domain's zone lives in Cloud DNS in this project, set its managed
# zone name here to auto-create the certificate's DNS authorization record.
# Leave blank to create that CNAME record by hand instead (see
# `terraform output dns_authorization_record` after apply).
dns_managed_zone_name = ""
