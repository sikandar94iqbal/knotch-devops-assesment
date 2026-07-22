#!/usr/bin/env bash
#
# teardown-prod.sh
#
# Tears down the `prod` environment. Same two options as teardown-dev.sh,
# but option 1 needs an extra step first: prod's GKE cluster and Cloud SQL
# instance both have `deletion_protection = true` by design (a stray
# `terraform destroy` can't take prod down by accident) - this script has
# to deliberately flip that to false, apply the flag change, destroy, and
# then restore the flag back to true in the source file afterward, so the
# repo is left in its normal protected-by-default state for next time.
#
# That's why this script asks for MORE confirmation than dev's, not less.

set -euo pipefail

PROJECT_ID="knotch-prod"
REPO_DIR="$(git rev-parse --show-toplevel)"
TF_DIR="$REPO_DIR/terraform/environments/prod"
MAIN_TF="$TF_DIR/main.tf"

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

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

section "Tear down: prod ($PROJECT_ID)"

echo "Prod has deletion_protection = true on both the GKE cluster and"
echo "Cloud SQL instance by design. Option 1 below has to deliberately"
echo "disable that - read the confirmation prompt carefully."
echo
echo "Two options:"
echo "  [1] terraform destroy  - removes the resources, keeps the GCP project"
echo "      (temporarily disables deletion_protection first, restores it after)"
echo "  [2] delete the project - fastest full wipe, bypasses deletion_protection"
echo "      entirely (project deletion doesn't check per-resource flags),"
echo "      recoverable ~30 days"
echo
read -r -p "Choose [1/2]: " choice

case "$choice" in
  1)
    confirm_destructive "About to (a) temporarily flip
deletion_protection from true to false for BOTH the GKE cluster and Cloud
SQL instance in terraform/environments/prod/main.tf, (b) apply that
change, (c) destroy every Terraform-managed resource in project
'$PROJECT_ID' - including the Cloud SQL instance and ALL DATA IN IT (any
point-in-time-recovery window ends the moment the instance is gone) -
and (d) restore deletion_protection back to true in main.tf afterward.
Step (c) cannot be undone once it completes. This is the safety net prod
normally has; disabling it is the entire point of running this script."

    cp "$MAIN_TF" "$MAIN_TF.pre-teardown.bak"
    sed -i -E 's/(deletion_protection[[:space:]]*=[[:space:]]*)true/\1false/' "$MAIN_TF"
    echo "deletion_protection flipped to false locally. Diff:"
    git -C "$REPO_DIR" diff -- "$MAIN_TF" || true

    cd "$TF_DIR"
    terraform init -input=false
    terraform apply -input=false -auto-approve
    echo "Protection disabled on the live resources."

    terraform plan -destroy -out=prod-destroy.tfplan
    echo
    echo "Plan above shows exactly what's about to be destroyed - last chance to Ctrl-C."

    terraform apply "prod-destroy.tfplan"
    rm -f prod-destroy.tfplan
    echo "Destroy complete."

    echo "Restoring deletion_protection = true in main.tf..."
    mv "$MAIN_TF.pre-teardown.bak" "$MAIN_TF"
    git -C "$REPO_DIR" diff -- "$MAIN_TF" || true
    echo
    echo "main.tf is back to its protected-by-default state, but that's an"
    echo "UNCOMMITTED local change right now (the git diff above should be"
    echo "empty, confirming it matches what's already in git - commit isn't"
    echo "needed unless the diff shows otherwise)."

    echo "The GCS bucket holding prod's Terraform state is NOT touched - it"
    echo "lives in the separate terraform/bootstrap stack."
    ;;
  2)
    confirm_destructive "Deletes the ENTIRE GCP project '$PROJECT_ID' -
bypasses deletion_protection entirely (project deletion doesn't check
individual resource protection flags), removes every resource in it, not
just what Terraform manages. Recoverable via
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
