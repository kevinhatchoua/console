#!/usr/bin/env bash
#
# Fix OLM bundle unpack failures on OpenShift CI / devcluster installs.
#
# Symptom: subscriptions stuck with BundleUnpackFailed because unpack jobs
# cannot pull registry.ci.openshift.org OLM utility images (expired pull secret
# or image only cached on one control-plane node).
#
# Usage (logged into the cluster):
#   ./contrib/fix-ci-cluster-olm.sh
#
# Optional: refresh registry.ci.openshift.org credentials first (Red Hat internal):
#   oc login --token=<app.ci-token> --server=https://api.ci.l2s4.p1.openshiftapps.com:6443
#   oc registry login --registry registry.ci.openshift.org --to=/tmp/ci-auth.json
#   # merge /tmp/ci-auth.json into openshift-config/pull-secret, then re-run this script.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! oc whoami >/dev/null 2>&1; then
  echo "Log in with oc first." >&2
  exit 1
fi

echo "Refreshing pull-secret copies for OLM namespaces..."
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d >"$WORKDIR/pull-secret.json"
for ns in openshift-marketplace openshift-operator-lifecycle-manager; do
  oc create secret generic pull-secret -n "$ns" --from-file=.dockerconfigjson="$WORKDIR/pull-secret.json" --dry-run=client -o yaml | oc apply -f -
  oc secrets link default pull-secret -n "$ns" --for=pull >/dev/null 2>&1 || true
done

echo "Finding a control-plane node with cached redhat-operators catalog image..."
CACHED_NODE=""
while IFS= read -r pod; do
  node=$(oc get pod -n openshift-marketplace "$pod" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  if [ -n "$node" ]; then
    CACHED_NODE="$node"
    break
  fi
done < <(oc get pods -n openshift-marketplace -l olm.catalogSource=redhat-operators -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -z "$CACHED_NODE" ]; then
  echo "Could not find a running redhat-operators catalog pod; using first control-plane node." >&2
  CACHED_NODE=$(oc get nodes -l node-role.kubernetes.io/master= -o jsonpath='{.items[0].metadata.name}')
fi
echo "Using node: $CACHED_NODE"

CORDONED=()
cleanup() {
  for node in "${CORDONED[@]}"; do
    oc adm uncordon "$node" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

echo "Cordoning other nodes so bundle-unpack jobs schedule on $CACHED_NODE..."
while IFS= read -r node; do
  if [ "$node" != "$CACHED_NODE" ]; then
    oc adm cordon "$node" >/dev/null
    CORDONED+=("$node")
  fi
done < <(oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

echo "Deleting stuck bundle-unpack jobs..."
oc delete jobs -n openshift-marketplace -l operatorframework.io/bundle-unpack-ref --ignore-not-found >/dev/null 2>&1 || true

echo "Waiting for bundle-unpack jobs to complete (up to 3 minutes)..."
deadline=$((SECONDS + 180))
while [ "$SECONDS" -lt "$deadline" ]; do
  pending=$(oc get jobs -n openshift-marketplace -l operatorframework.io/bundle-unpack-ref --no-headers 2>/dev/null | awk '$2 != "1/1" && $2 != "Complete" {print}' | wc -l | tr -d ' ')
  failing=$(oc get pods -n openshift-marketplace -l operatorframework.io/bundle-unpack-ref --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$pending" = "0" ]; then
    break
  fi
  if [ "$failing" != "0" ]; then
    echo "Bundle unpack pods failed; retrying job deletion once..." >&2
    oc delete jobs -n openshift-marketplace -l operatorframework.io/bundle-unpack-ref --field-selector status.successful!=1 --ignore-not-found >/dev/null 2>&1 || true
  fi
  sleep 10
done

echo "Subscription status:"
oc get subscription -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CSV:.status.currentCSV,REASON:.status.conditions[-1].reason' 2>/dev/null || true

echo ""
echo "Done. If subscriptions are still stuck, refresh registry.ci.openshift.org auth in openshift-config/pull-secret (see script header)."
