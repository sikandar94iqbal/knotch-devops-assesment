# The PROD GCP project - must be a DIFFERENT project ID than dev's
# (terraform/environments/dev/terraform.tfvars). See the same note in
# dev/terraform.tfvars: separate projects are what actually isolate dev
# from prod, not just separate name prefixes within one shared project.
project_id = "knotch-prod"
region     = "us-central1"

# Hostname the Gateway serves and the managed TLS cert covers.
hostname = "REPLACE_WITH_HOSTNAME.example.com"

# ArgoCD's own hostname - separate Gateway/cert from the app's, but same
# managed-cert/Cloud Armor treatment. Never a separate public LoadBalancer.
argocd_hostname = "REPLACE_WITH_ARGOCD_HOSTNAME.example.com"

# If this domain's zone lives in Cloud DNS in this project, set its managed
# zone name here to auto-create the certificate's DNS authorization record.
# Leave blank to create that CNAME record by hand instead (see
# `terraform output dns_authorization_record` after apply).
dns_managed_zone_name = ""
