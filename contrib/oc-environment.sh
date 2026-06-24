# shellcheck shell=bash
#
# This file is an example of how you might set up your environment to run the
# console against an OpenShift cluster during development. To use it for
# running bridge, do
#
# . contrib/oc-environment.sh
# ./bin/bridge
#
# You'll need oc, and you'll need to be logged into a cluster.
#
# The environment variables beginning with "BRIDGE_" act just like bridge
# command line arguments - in fact. to get more information about any of them,
# you can run ./bin/bridge --help

BRIDGE_USER_AUTH="disabled"
export BRIDGE_USER_AUTH

BRIDGE_K8S_MODE="off-cluster"
export BRIDGE_K8S_MODE

BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT=$(oc whoami --show-server)
export BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT

BRIDGE_K8S_MODE_OFF_CLUSTER_SKIP_VERIFY_TLS=true
export BRIDGE_K8S_MODE_OFF_CLUSTER_SKIP_VERIFY_TLS

BRIDGE_K8S_MODE_OFF_CLUSTER_THANOS=$(oc -n openshift-config-managed get configmap monitoring-shared-config -o jsonpath='{.data.thanosPublicURL}')
export BRIDGE_K8S_MODE_OFF_CLUSTER_THANOS

BRIDGE_K8S_MODE_OFF_CLUSTER_ALERTMANAGER=$(oc -n openshift-config-managed get configmap monitoring-shared-config -o jsonpath='{.data.alertmanagerPublicURL}')
export BRIDGE_K8S_MODE_OFF_CLUSTER_ALERTMANAGER

GITOPS_HOSTNAME=$(oc -n openshift-gitops get route cluster -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$GITOPS_HOSTNAME" ]; then
    BRIDGE_K8S_MODE_OFF_CLUSTER_GITOPS="https://$GITOPS_HOSTNAME"
    export BRIDGE_K8S_MODE_OFF_CLUSTER_GITOPS
fi

# This route will not exist by default. If we want olmv1 to work off cluster, we will need to
# manually create a route for the catalogd service.
CATALOGD_HOSTNAME=$(oc -n openshift-catalogd get route catalogd-route -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "$CATALOGD_HOSTNAME" ]; then
    BRIDGE_K8S_MODE_OFF_CLUSTER_CATALOGD="https://$CATALOGD_HOSTNAME"
    export BRIDGE_K8S_MODE_OFF_CLUSTER_CATALOGD
fi

# Prefer long-lived SA token (examples/secret.yaml + oc extract) over short-lived user tokens.
if [ -f "./examples/token" ]; then
  BRIDGE_K8S_AUTH_BEARER_TOKEN=$(cat ./examples/token)
  BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE=./examples/token
  BRIDGE_USE_LONG_LIVED_TOKEN=1
else
  BRIDGE_K8S_AUTH_BEARER_TOKEN=$(oc whoami --show-token)
fi
export BRIDGE_K8S_AUTH_BEARER_TOKEN
export BRIDGE_USE_LONG_LIVED_TOKEN

BRIDGE_USER_SETTINGS_LOCATION="localstorage"
export BRIDGE_USER_SETTINGS_LOCATION

# Use Red Hat OpenShift product branding (masthead logo, favicon, title) for local dev.
BRIDGE_BRANDING="ocp"
export BRIDGE_BRANDING

# This is a workaround for local setup where Helm CLI has been setup with helm repositories
HELM_REPOSITORY_CONFIG="/tmp/repositories.yaml"
export HELM_REPOSITORY_CONFIG


# Bearer token file for bridge API proxy (re-read from disk on each request).
if [ -f "./examples/token" ]; then
  BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE=./examples/token
elif [ -n "${BRIDGE_K8S_AUTH_BEARER_TOKEN:-}" ]; then
  temp_file=$(mktemp)
  echo "$BRIDGE_K8S_AUTH_BEARER_TOKEN" >"$temp_file"
  BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE=$temp_file
fi
export BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE

echo "Using $BRIDGE_K8S_MODE_OFF_CLUSTER_ENDPOINT"
