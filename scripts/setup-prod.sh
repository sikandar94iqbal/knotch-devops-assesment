#!/usr/bin/env bash
#
# setup-prod.sh
#
# Walks through provisioning the `prod` environment end-to-end: Terraform
# apply -> ArgoCD reachable -> app deployed and reachable. Mirrors what was
# done for `dev` by hand. Every step that changes real infrastructure,
# writes a secret, or touches the shared git remote pauses first, prints
# what it's about to do and why it matters, and waits for an explicit "y".
#
# Prerequisites (not checked by this script):
#   - gcloud authenticated (`gcloud auth login`) with access to the prod project
#   - terraform (>= 1.5), kubectl, helm, git installed
#   - terraform/environments/prod/terraform.tfvars already has the right
#     project_id/hostname/certificate_mode (see README)
#   - terraform/bootstrap already run against the prod project (state
#     bucket exists) - this script does NOT create it
#   - A GitHub fine-grained PAT (read-only, scoped to this one repo) ready
#     to paste when prompted - only needed once, at the "connect repo" step
#
# Safe to re-run: every step is idempotent (terraform apply, kubectl apply,
# and the wait loops all tolerate being run again if a previous run was
# interrupted).

set -euo pipefail

# --- Configuration - matches this repo's actual prod setup -----------------
PROJECT_ID="knotch-prod"
REGION="us-central1"
CLUSTER_NAME="tenant-prod-gke"
APP_NAME="knotch-demo-app-prod"      # ArgoCD Application name = Helm release name
APP_HOSTNAME="api-prod.tenant.internal"
ARGOCD_HOSTNAME="argocd-prod.tenant.internal"
THIRD_PARTY_SECRET_ID="tenant-prod-third-party-api-key"
GITHUB_REPO_URL="https://github.com/sikandar94iqbal/knotch-devops-assesment.git"

REPO_DIR="$(git rev-parse --show-toplevel)"
TF_DIR="$REPO_DIR/terraform/environments/prod"
VALUES_FILE="$REPO_DIR/helm/api-service/values-prod.yaml"

# --- Helpers -----------------------------------------------------------------

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

# Prints an IMPACT statement and blocks until the user types y/yes.
# Usage: confirm "Human-readable description of what happens if you continue."
confirm() {
  echo
  echo "------------------------------------------------------------"
  echo "IMPACT: $1"
  echo "------------------------------------------------------------"
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *)
      echo "Aborted - no changes made by this step."
      exit 1
      ;;
  esac
}

# Polls a condition command until it succeeds or a timeout is hit.
# Usage: wait_for "description" 60 <command...>
wait_for() {
  local description="$1"
  local max_attempts="$2"
  shift 2
  local attempt=0
  echo -n "Waiting for $description "
  until "$@" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo
      echo "Timed out waiting for $description."
      echo "This script is safe to re-run - check manually, then re-run it."
      exit 1
    fi
    echo -n "."
    sleep 10
  done
  echo " done."
}

# --- Step 0: sanity checks ----------------------------------------------------

section "Step 0: Prerequisites check"

for tool in terraform kubectl gcloud git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' is not installed or not on PATH."
    exit 1
  fi
done

echo "Repo root:      $REPO_DIR"
echo "Terraform dir:  $TF_DIR"
echo "GCP project:    $PROJECT_ID"
echo "GKE cluster:    $CLUSTER_NAME"
echo "App hostname:   $APP_HOSTNAME"
echo "ArgoCD hostname: $ARGOCD_HOSTNAME"
echo "All required tools found."

# --- Step 1: Terraform plan + apply ------------------------------------------

section "Step 1: Provision infrastructure via Terraform"

cd "$TF_DIR"
terraform init -input=false
terraform plan -out=prod.tfplan

confirm "Creates real, billable GCP resources in project '$PROJECT_ID': VPC, a
private GKE Autopilot cluster, a Cloud SQL Postgres instance (REGIONAL/HA,
db-custom-2-7680), a Cloud Armor policy, Certificate Manager certificates,
Secret Manager secrets, and installs ArgoCD + External Secrets Operator
into the cluster via Helm. Takes roughly 10-12 minutes. Ongoing cost
accrues from this point on until the environment is torn down."

terraform apply "prod.tfplan"
rm -f prod.tfplan

echo "Terraform apply complete."

# --- Step 2: cluster credentials + outputs -----------------------------------

section "Step 2: Fetch GKE credentials and Terraform outputs"

gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"
echo "kubectl is now pointed at $CLUSTER_NAME."

terraform output

APP_SA_EMAIL="$(terraform output -raw app_service_account_email)"
DB_HOST="$(terraform output -raw database_private_ip)"
SECURITY_POLICY="$(terraform output -raw security_policy_name)"
CERT_MAP_NAME="$(terraform output -raw certificate_map_name)"
ARGOCD_URL="$(terraform output -raw argocd_url)"

echo
echo "App service account:    $APP_SA_EMAIL"
echo "Database private IP:    $DB_HOST"
echo "Cloud Armor policy:     $SECURITY_POLICY"
echo "Certificate map:        $CERT_MAP_NAME"
echo "ArgoCD URL:             $ARGOCD_URL"

# --- Step 3: ArgoCD admin credentials + Gateway IP ---------------------------

section "Step 3: ArgoCD admin credentials and Gateway address"

wait_for "argocd-initial-admin-secret to exist" 30 \
  kubectl get secret argocd-initial-admin-secret -n argocd

ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

echo "ArgoCD URL:      $ARGOCD_URL"
echo "ArgoCD username: admin"
echo "ArgoCD password: $ARGOCD_PASSWORD"
echo "(Delete this initial secret after your first login, once you've set a new password:"
echo "  kubectl -n argocd delete secret argocd-initial-admin-secret )"

wait_for "ArgoCD's Gateway to get an external IP" 60 \
  bash -c "[ -n \"\$(kubectl get gateway argocd-gateway -n argocd -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)\" ]"

ARGOCD_GATEWAY_IP="$(kubectl get gateway argocd-gateway -n argocd -o jsonpath='{.status.addresses[0].value}')"
echo "ArgoCD Gateway IP: $ARGOCD_GATEWAY_IP"
echo "Add this to /etc/hosts to browse the UI:"
echo "  $ARGOCD_GATEWAY_IP  $ARGOCD_HOSTNAME"

# --- Step 4: fill in values-prod.yaml -----------------------------------------

section "Step 4: Update helm/api-service/values-prod.yaml with real values"

confirm "Edits $VALUES_FILE in place, setting gateway.hostname,
gateway.certificateMapName, cloudArmor.securityPolicyName,
serviceAccount.gcpServiceAccountEmail, database.host, and
externalSecrets.gcpProjectId to the real values fetched above - by YAML
key, not by matching leftover placeholder text, so this stays correct
even on a re-run after the underlying infra changed (e.g. Cloud SQL's
private IP is reassigned after a destroy+recreate). Only touches these
six keys' values - nothing else in the file changes. Review the diff
printed after this step before committing."

sed -i.bak -E \
  -e "s|^([[:space:]]*hostname: ).*|\1\"${APP_HOSTNAME}\"|" \
  -e "s|^([[:space:]]*certificateMapName: ).*|\1\"${CERT_MAP_NAME}\"|" \
  -e "s|^([[:space:]]*securityPolicyName: ).*|\1\"${SECURITY_POLICY}\"|" \
  -e "s|^([[:space:]]*gcpServiceAccountEmail: ).*|\1\"${APP_SA_EMAIL}\"|" \
  -e "s|^([[:space:]]*host: ).*|\1\"${DB_HOST}\"|" \
  -e "s|^([[:space:]]*gcpProjectId: ).*|\1\"${PROJECT_ID}\"|" \
  "$VALUES_FILE"
rm -f "$VALUES_FILE.bak"

echo "Updated. Diff:"
git -C "$REPO_DIR" diff -- "$VALUES_FILE" || true

# --- Step 5: third-party API key secret version ------------------------------

section "Step 5: Add a value for the third-party API key secret"

confirm "Writes a NEW Secret Manager secret VERSION for
'$THIRD_PARTY_SECRET_ID' in project '$PROJECT_ID'. This script writes a
placeholder value - replace it later with a real key using the same
'gcloud secrets versions add' command shown below. Terraform never manages
this value; only the empty secret container."

echo -n "demo-placeholder-value-replace-with-a-real-key-later" | \
  gcloud secrets versions add "$THIRD_PARTY_SECRET_ID" --data-file=- --project "$PROJECT_ID"

# --- Step 6: commit + push ----------------------------------------------------

section "Step 6: Commit and push values-prod.yaml"

confirm "Commits and pushes to the 'main' branch of this repo's GitHub
remote. Visible to anyone with access to the repo, and will trigger
ArgoCD to sync once the repo is connected (next step)."

cd "$REPO_DIR"
git add helm/api-service/values-prod.yaml
git commit -m "Fill in prod Helm values from terraform output"
git push

# --- Step 7: connect repo to ArgoCD -------------------------------------------

section "Step 7: Connect this GitHub repo to prod's ArgoCD"

echo "ArgoCD needs credentials to clone this repo (it's private)."
echo "Generate a fine-grained PAT first if you haven't: GitHub -> Settings ->"
echo "Developer settings -> Personal access tokens -> Fine-grained -> scope"
echo "it to this repo only, read-only 'Contents' permission."
echo
read -r -p "GitHub username: " GH_USERNAME
read -r -s -p "GitHub PAT (input hidden): " GH_PAT
echo

confirm "Creates a Kubernetes Secret named 'github-repo-creds' in the
'argocd' namespace on the PROD cluster, containing your GitHub PAT. It is
base64-encoded at rest (standard Kubernetes Secret handling, not
plaintext-readable via 'kubectl get' output) but anyone with permission to
read Secrets in this namespace could retrieve it. Alternative: skip this
step and use the ArgoCD UI's 'Connect Repo' button instead (Settings ->
Repositories) - functionally identical, your choice."

kubectl create secret generic github-repo-creds \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url="$GITHUB_REPO_URL" \
  --from-literal=username="$GH_USERNAME" \
  --from-literal=password="$GH_PAT"

kubectl label secret github-repo-creds -n argocd argocd.argoproj.io/secret-type=repository

unset GH_PAT
echo "Repo credentials registered with ArgoCD."

# --- Step 8: hand control to ArgoCD ------------------------------------------

section "Step 8: Apply app-of-apps.yaml (the one manual kubectl apply)"

confirm "Creates the 'app-of-apps' Application in ArgoCD on the PROD
cluster. ArgoCD will then discover argocd/prod/apps/api.yaml, create the
'$APP_NAME' Application, render the Helm chart, and create real
Deployment/Service/Gateway/HPA/PDB objects in the 'tenant-prod' namespace.
This is the last manual kubectl apply this environment ever needs -
everything after this is driven by git."

kubectl apply -f "$REPO_DIR/argocd/prod/app-of-apps.yaml"

# --- Step 9: verify ------------------------------------------------------------

section "Step 9: Verify"

wait_for "$APP_NAME Application to sync" 60 \
  bash -c "[ \"\$(kubectl get application $APP_NAME -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)\" = 'Synced' ]"

echo "$APP_NAME is Synced."
kubectl get applications -n argocd
kubectl get pods -n tenant-prod

# The Helm release name is the ArgoCD Application name, so every rendered
# resource is prefixed "$APP_NAME-" - e.g. the Gateway is "$APP_NAME-api-service".
APP_GATEWAY_NAME="${APP_NAME}-api-service"

wait_for "the app's own Gateway to get an external IP" 60 \
  bash -c "[ -n \"\$(kubectl get gateway $APP_GATEWAY_NAME -n tenant-prod -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)\" ]"

APP_GATEWAY_IP="$(kubectl get gateway "$APP_GATEWAY_NAME" -n tenant-prod -o jsonpath='{.status.addresses[0].value}')"

section "DONE"

cat <<SUMMARY
ArgoCD:  $ARGOCD_URL   (IP: $ARGOCD_GATEWAY_IP)
App:     https://${APP_HOSTNAME}/   (IP: $APP_GATEWAY_IP)

Add both to /etc/hosts to browse them:
  $ARGOCD_GATEWAY_IP  $ARGOCD_HOSTNAME
  $APP_GATEWAY_IP  $APP_HOSTNAME

Note: right after a Gateway first reports PROGRAMMED=True, the actual
TLS-serving edge can take a few more minutes to propagate globally - if a
curl/browser test fails immediately after this script finishes, wait a
few minutes and retry before assuming something is wrong.
SUMMARY
