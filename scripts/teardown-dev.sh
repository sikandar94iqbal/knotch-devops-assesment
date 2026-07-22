#!/usr/bin/env bash
#
# teardown-dev.sh
#
# Tears down the `dev` environment. Offers the same two options documented
# in the README's "Tear it down" section:
#   [1] terraform destroy  - removes the resources, keeps the GCP project
#   [2] delete the project - fastest full wipe, ~30-day recovery window
#
# Dev has deletion_protection = false everywhere, so option 1 needs no
# special handling - contrast with teardown-prod.sh, which has to
# deliberately disable protection first.

set -euo pipefail

PROJECT_ID="knotch-dev"
REPO_DIR="$(git rev-parse --show-toplevel)"
TF_DIR="$REPO_DIR/terraform/environments/dev"

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

# Requires typing the project ID back, not just "y" - a stray Enter or a
# pasted "y" from clipboard history shouldn't be able to destroy an
# environment.
confirm_destructive() {
  local impact="$1"
  echo
  echo "############################################################"
  echo "DESTRUCTIVE ACTION: $impact"
  echo "############################################################"
  read -r -p "Type '$PROJECT_ID' to confirm, anything else cancels: " reply
  if [ "$reply" != "$PROJECT_ID" ]; then
    echo "Cancelled - no changes made."
    exit 1
  fi
}

section "Tear down: dev ($PROJECT_ID)"

echo "Two options:"
echo "  [1] terraform destroy  - removes the resources, keeps the GCP project"
echo "  [2] delete the project - fastest full wipe, recoverable ~30 days"
echo
read -r -p "Choose [1/2]: " choice

case "$choice" in
  1)
    cd "$TF_DIR"
    terraform init -input=false
    terraform plan -destroy -out=dev-destroy.tfplan

    confirm_destructive "Destroys every Terraform-managed resource in
project '$PROJECT_ID': the GKE cluster (and everything running on it -
the app, ArgoCD, External Secrets Operator), the Cloud SQL instance and
ALL DATA IN IT (dev has no deletion protection and no point-in-time
recovery), the VPC, Cloud Armor policy, certificates, and secrets. Cannot
be undone once it completes. The GCS bucket holding this environment's
Terraform state is NOT touched - it lives in the separate
terraform/bootstrap stack and needs its own explicit teardown if you want
it gone too (see the README - it has extra protection since it holds
every environment's state, not just dev's)."

    terraform apply "dev-destroy.tfplan"
    rm -f dev-destroy.tfplan
    echo "Destroy complete."
    ;;
  2)
    confirm_destructive "Deletes the ENTIRE GCP project '$PROJECT_ID' -
every resource in it, not just what Terraform manages. Recoverable via
'gcloud projects undelete $PROJECT_ID' for about 30 days, then
permanently gone."

    gcloud projects delete "$PROJECT_ID"
    echo "Project deletion initiated. Undo within ~30 days with:"
    echo "  gcloud projects undelete $PROJECT_ID"
    ;;
  *)
    echo "Invalid choice - expected 1 or 2. Aborting, nothing changed."
    exit 1
    ;;
esac
