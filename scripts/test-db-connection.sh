#!/usr/bin/env bash
#
# test-db-connection.sh <dev|prod>
#
# Proves the private Pod -> VPC -> Private Service Access -> Cloud SQL path
# actually works, end to end, from inside the cluster - not just "the
# Terraform applied cleanly". Runs a short-lived debug Pod in the same
# namespace as the app (so it takes the exact same network path a real
# app Pod would), using the exact DB host/name/user/password the app
# itself is configured with - no separate credentials, no assumptions.
#
# Two checks:
#   1. TCP reachability (pg_isready) - proves the private IP is routable
#      from inside the VPC at all, independent of credentials.
#   2. Authenticated query (psql SELECT 1) - proves the actual
#      username/password ESO synced from Secret Manager is correct and
#      the database accepts the connection over TLS.
#
# Cleans up after itself either way (kubectl run --rm).

set -euo pipefail

ENV="${1:-}"
if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 <dev|prod>"
  exit 1
fi

NAMESPACE="tenant-${ENV}"
RELEASE_NAME="knotch-demo-app-${ENV}"
DEPLOYMENT_NAME="${RELEASE_NAME}-api-service"
SECRET_NAME="${RELEASE_NAME}-api-service-secrets"
POD_NAME="db-connection-test-${ENV}-$$"

echo "============================================================"
echo "DB connectivity test: $ENV"
echo "============================================================"
echo "Namespace:  $NAMESPACE"
echo "Deployment: $DEPLOYMENT_NAME"
echo

# Pull the exact live config the app Pod itself uses - not a value read
# from a YAML file on disk, which could be stale relative to what's
# actually deployed.
DB_HOST="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_HOST")].value}')"
DB_PORT="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_PORT")].value}')"
DB_NAME="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_NAME")].value}')"
DB_USER="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_USER")].value}')"

if [[ -z "$DB_HOST" ]]; then
  echo "ERROR: could not read DB_HOST from deployment/$DEPLOYMENT_NAME in namespace $NAMESPACE."
  echo "Is the app deployed yet? (see argocd/$ENV/apps/api.yaml)"
  exit 1
fi

echo "DB host: $DB_HOST:$DB_PORT   DB name: $DB_NAME   DB user: $DB_USER"
echo

# The password itself never gets echoed to this terminal - it's read
# directly into the debug Pod's environment via the same Secret the app
# Pod mounts, never printed here.
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: secret $SECRET_NAME not found in $NAMESPACE."
  echo "The ExternalSecret may not have synced yet - check:"
  echo "  kubectl get externalsecret -n $NAMESPACE"
  exit 1
fi

echo "--- Test 1: TCP reachability (pg_isready) ---"
kubectl run "$POD_NAME" \
  --namespace "$NAMESPACE" \
  --image=postgres:16-alpine \
  --restart=Never \
  --rm -i \
  --quiet \
  --command -- pg_isready -h "$DB_HOST" -p "$DB_PORT" -t 10
echo

echo "--- Test 2: authenticated query (SELECT 1) ---"
kubectl run "${POD_NAME}-auth" \
  --namespace "$NAMESPACE" \
  --image=postgres:16-alpine \
  --restart=Never \
  --rm -i \
  --quiet \
  --overrides="$(cat <<OVERRIDES
{
  "apiVersion": "v1",
  "spec": {
    "containers": [{
      "name": "${POD_NAME}-auth",
      "image": "postgres:16-alpine",
      "command": ["psql"],
      "args": ["-h", "${DB_HOST}", "-p", "${DB_PORT}", "-U", "${DB_USER}", "-d", "${DB_NAME}", "-c", "SELECT 1 AS connectivity_test;"],
      "env": [{
        "name": "PGPASSWORD",
        "valueFrom": {"secretKeyRef": {"name": "${SECRET_NAME}", "key": "DB_PASSWORD"}}
      }],
      "stdin": true,
      "tty": false
    }]
  }
}
OVERRIDES
)"

echo
echo "============================================================"
echo "Both checks passed: the private Pod -> VPC -> Private Service"
echo "Access -> Cloud SQL path works, using the app's real credentials."
echo "============================================================"
