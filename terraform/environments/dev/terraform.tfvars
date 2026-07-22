# The DEV GCP project - must be a DIFFERENT project ID than prod's
# (terraform/environments/prod/terraform.tfvars). Separate projects keep
# dev's IAM, quotas, and blast radius fully isolated from prod's - a
# runaway resource or an over-broad role binding here has no way to touch
# prod, because it's a different project entirely, not just a different
# VPC/cluster within one shared project.
project_id = "knotch-dev"
region     = "us-central1"

# No real domain registered yet: certificate_mode = "self_signed" makes
# Terraform generate and upload a self-signed cert for this hostname, so
# the Gateway serves real HTTPS without any DNS validation. This hostname
# doesn't need to resolve anywhere public - map it to the Gateway's IP in
# your local /etc/hosts (or use `curl --resolve`) to test.
#
# Once you have a real domain: change this to the real hostname, flip
# certificate_mode to "managed" below, and re-`apply` - the cert map entry
# just starts pointing at a real, DNS-validated certificate instead.
hostname         = "api-dev.tenant.internal"
certificate_mode = "self_signed"

# ArgoCD's own hostname - same self-signed/no-domain approach, same
# certificate_mode above. ArgoCD is exposed through its own Gateway, never
# a separate public LoadBalancer.
argocd_hostname = "argocd-dev.tenant.internal"

# Only relevant when certificate_mode = "managed" and the domain's zone
# lives in Cloud DNS in this project.
dns_managed_zone_name = ""
