#!/usr/bin/env bash
#
# test-db-connection.sh <dev|prod>
#   or: ENV=<dev|prod> test-db-connection.sh
#
# Proves the private Pod -> VPC -> Private Service Access -> Cloud SQL path
# actually works, end to end - and does it from inside a REAL, currently
# running app Pod, not a standalone bystander Pod. That distinction
# matters: the app's NetworkPolicy (helm/api-service/templates/networkpolicy.yaml)
# scopes its egress rule to Pods carrying the app's own selector labels. A
# plain `kubectl run` debug Pod doesn't carry those labels, so it isn't
# governed by that NetworkPolicy at all - it would pass even if the
# NetworkPolicy's egress rule were broken. Attaching an ephemeral debug
# container to the actual app Pod (via `kubectl debug`) shares that Pod's
# network namespace, so it's subject to the exact same NetworkPolicy
# enforcement a real request from the app would be.
#
# Which environment to test can be given either as a positional argument
# or as the ENV environment variable (handy for CI or for scripting
# against both environments in one loop, e.g.
# `for e in dev prod; do ENV=$e ./scripts/test-db-connection.sh; done`).
# The positional argument wins if both are set.
#
# Two checks, both run as an ephemeral container attached to a live app Pod:
#   1. TCP reachability (pg_isready) - proves the private IP is routable
#      from inside the VPC, through the app's own NetworkPolicy egress rule.
#   2. Authenticated query (psql SELECT 1) - proves the actual
#      username/password ESO synced from Secret Manager is correct and
#      the database accepts the connection over TLS.
#
# The debug container runs as root (overriding the Pod's own non-root
# securityContext for just this one ephemeral container) - postgres:16-alpine's
# client tools call getpwuid() to resolve the current user's home directory,
# which fails for an arbitrary UID with no /etc/passwd entry and makes
# pg_isready/psql abort before ever attempting the connection. Root inside a
# short-lived diagnostic container doesn't touch the real app container's
# security posture; it's the same access GKE's own `kubectl debug` docs
# assume you'll use for exactly this kind of image swap.
#
# Known limitation: Kubernetes has no way to remove an ephemeral container
# once added - it stays listed (terminated, zero resource cost) in the
# Pod's spec until that Pod is replaced. Routine rollouts/scaling naturally
# clear it eventually; it's not a leak, just a permanent-until-replaced
# entry in `kubectl describe pod` output.

set -euo pipefail

ENV="${1:-${ENV:-}}"
if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
  echo "Usage: $0 <dev|prod>"
  echo "   or: ENV=<dev|prod> $0"
  exit 1
fi

NAMESPACE="tenant-${ENV}"
RELEASE_NAME="knotch-demo-app-${ENV}"
DEPLOYMENT_NAME="${RELEASE_NAME}-api-service"
SECRET_NAME="${RELEASE_NAME}-api-service-secrets"
LABEL_SELECTOR="app.kubernetes.io/name=api-service,app.kubernetes.io/instance=${RELEASE_NAME}"

echo "============================================================"
echo "DB connectivity test: $ENV (from a live app Pod)"
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

if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: secret $SECRET_NAME not found in $NAMESPACE."
  echo "The ExternalSecret may not have synced yet - check:"
  echo "  kubectl get externalsecret -n $NAMESPACE"
  exit 1
fi

# A real, currently Running app Pod - this is what gets the ephemeral
# debug container attached, so the test rides the app's actual network
# namespace and NetworkPolicy enforcement, not a bystander's.
APP_POD="$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$APP_POD" ]]; then
  echo "ERROR: no Running Pod found for $LABEL_SELECTOR in $NAMESPACE."
  echo "Is the app deployed and healthy yet? (see argocd/$ENV/apps/api.yaml)"
  exit 1
fi

APP_CONTAINER="$(kubectl get pod "$APP_POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].name}')"

echo "Testing from live app Pod: $APP_POD (container: $APP_CONTAINER)"
echo

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Ephemeral containers inherit the Pod's own securityContext (runAsUser
# from the app's non-root podSecurityContext) unless overridden here.
# postgres:16-alpine's client tools need a resolvable passwd entry for
# their running UID (getpwuid()) or they abort before even attempting the
# connection - root always has one. This only affects this one throwaway
# diagnostic container, never the real app container.
cat >"$TMP_DIR/plain.json" <<JSON
{
  "securityContext": {
    "runAsUser": 0,
    "runAsNonRoot": false
  }
}
JSON

cat >"$TMP_DIR/auth.json" <<JSON
{
  "securityContext": {
    "runAsUser": 0,
    "runAsNonRoot": false
  },
  "env": [
    {
      "name": "PGPASSWORD",
      "valueFrom": {
        "secretKeyRef": {
          "name": "${SECRET_NAME}",
          "key": "DB_PASSWORD"
        }
      }
    }
  ]
}
JSON

# Polls until the named ephemeral container reaches a terminal state,
# rather than trusting `kubectl debug --attach` (which can race container
# startup and silently report a false pass - confirmed while building
# this script). Prints the exit code, or "TIMEOUT" after ~30s.
wait_for_ephemeral_exit() {
  local container="$1"
  local attempt
  for ((attempt = 1; attempt <= 15; attempt++)); do
    local exit_code
    exit_code="$(kubectl get pod "$APP_POD" -n "$NAMESPACE" \
      -o jsonpath="{.status.ephemeralContainerStatuses[?(@.name==\"${container}\")].state.terminated.exitCode}" \
      2>/dev/null || true)"
    if [[ -n "$exit_code" ]]; then
      echo "$exit_code"
      return 0
    fi
    sleep 2
  done
  echo "TIMEOUT"
}

echo "--- Test 1: TCP reachability (pg_isready), from the app Pod's own network namespace ---"
CONTAINER_1="db-test-plain-$$"
kubectl debug "$APP_POD" -n "$NAMESPACE" \
  --image=postgres:16-alpine \
  -c "$CONTAINER_1" \
  --target="$APP_CONTAINER" \
  --profile=general \
  --custom="$TMP_DIR/plain.json" \
  --quiet \
  -- pg_isready -h "$DB_HOST" -p "$DB_PORT" -t 10 >/dev/null 2>&1 || true

EXIT_1="$(wait_for_ephemeral_exit "$CONTAINER_1")"
kubectl logs "$APP_POD" -n "$NAMESPACE" -c "$CONTAINER_1" 2>/dev/null || true
if [[ "$EXIT_1" != "0" ]]; then
  echo "FAILED: pg_isready exited $EXIT_1 (or timed out waiting for it)."
  exit 1
fi
echo

echo "--- Test 2: authenticated query (SELECT 1), same Pod, real credentials ---"
CONTAINER_2="db-test-auth-$$"
kubectl debug "$APP_POD" -n "$NAMESPACE" \
  --image=postgres:16-alpine \
  -c "$CONTAINER_2" \
  --target="$APP_CONTAINER" \
  --profile=general \
  --custom="$TMP_DIR/auth.json" \
  --quiet \
  -- psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 AS connectivity_test;" >/dev/null 2>&1 || true

EXIT_2="$(wait_for_ephemeral_exit "$CONTAINER_2")"
kubectl logs "$APP_POD" -n "$NAMESPACE" -c "$CONTAINER_2" 2>/dev/null || true
if [[ "$EXIT_2" != "0" ]]; then
  echo "FAILED: authenticated query exited $EXIT_2 (or timed out waiting for it)."
  exit 1
fi

echo
echo "============================================================"
echo "Both checks passed, run from inside the real app Pod ($APP_POD):"
echo "the private Pod -> VPC -> Private Service Access -> Cloud SQL path"
echo "works, through the app's own NetworkPolicy, with its real credentials."
echo "============================================================"
