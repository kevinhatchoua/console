#!/usr/bin/env bash
#
# Run local Bridge with the same dynamic plugins and perspective customization
# as the in-cluster console. Required because contrib/oc-environment.sh only
# configures API access — it does not load Console operator plugins/customization.
#
# Usage (from repo root):
#   ./contrib/local-console-daemon.sh              # recommended: auto-recover when online
#   ./contrib/install-local-console-autostart.sh # macOS: run daemon at login
#
# Manual (yarn dev must be running on :8080):
#   ./contrib/local-console-with-cluster-plugins.sh
#
# Options:
#   --managed-by-daemon   Used by local-console-daemon.sh (writes pid file, logs to file)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANAGED_BY_DAEMON=false
for arg in "$@"; do
  if [ "$arg" = "--managed-by-daemon" ]; then
    MANAGED_BY_DAEMON=true
  fi
done

# shellcheck source=contrib/local-console-lib.sh
source "$ROOT_DIR/contrib/local-console-lib.sh"

STATE_DIR="${ROOT_DIR}/.local-console"
BRIDGE_PID_FILE="${STATE_DIR}/bridge.pid"
mkdir -p "$STATE_DIR"

if ! local_console_cluster_reachable; then
  if [ "$MANAGED_BY_DAEMON" = true ]; then
    echo "Cluster not reachable; daemon will retry." >&2
    exit 1
  fi
  echo "Log in with oc first." >&2
  exit 1
fi

# oc-environment.sh runs optional oc lookups that may fail on minimal clusters
set +e
# shellcheck source=contrib/oc-environment.sh
source "$ROOT_DIR/contrib/oc-environment.sh"
set -euo pipefail

PF_PIDS=()
start_pf() {
  local label=$1
  shift
  # Restart port-forwards after VPN/network drops (oc port-forward exits when disconnected).
  (
    while true; do
      if oc "$@" 2>/dev/null; then
        echo "  port-forward $label disconnected, restarting in 3s..." >&2
        sleep 3
      else
        echo "  port-forward $label unavailable, retrying in 30s..." >&2
        sleep 30
      fi
    done
  ) &
  PF_PIDS+=("$!")
  echo "  port-forward $label (supervisor pid $!)"
}

start_token_refresh() {
  if [ "${BRIDGE_USE_LONG_LIVED_TOKEN:-}" = "1" ]; then
    echo "  using long-lived token from examples/token"
    return 0
  fi
  if [ -z "${BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE:-}" ]; then
    return 0
  fi
  local token_file=$BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE
  (
    while true; do
      sleep 300
      local_console_refresh_token || true
    done
  ) &
  PF_PIDS+=("$!")
  echo "  token refresh (pid $!, every 5m)"
}

start_connectivity_watchdog() {
  (
    local was_offline=false
    while true; do
      if local_console_cluster_reachable; then
        if [ "$was_offline" = true ]; then
          echo "  cluster reachable again — refreshing token and browser..." >&2
          local_console_refresh_token || true
          sleep 5
          local_console_reload_browser
          local_console_notify "OpenShift console reconnected"
          was_offline=false
        fi
      else
        was_offline=true
      fi
      sleep "${LOCAL_CONSOLE_POLL_INTERVAL:-30}"
    done
  ) &
  PF_PIDS+=("$!")
  echo "  connectivity watchdog (pid $!)"
}

cleanup() {
  rm -f "$BRIDGE_PID_FILE"
  for pid in "${PF_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
    pkill -P "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "Starting plugin port-forwards..."
start_pf networking-console-plugin -n openshift-network-console port-forward svc/networking-console-plugin 19443:9443
start_pf monitoring-plugin           -n openshift-monitoring port-forward svc/monitoring-plugin 19444:9443
start_pf mce                         -n multicluster-engine port-forward svc/console-mce-console 19300:3000
start_pf acm                         -n open-cluster-management port-forward svc/console-chart-console-v2 19301:3000
start_pf kubevirt-plugin             -n openshift-cnv port-forward svc/kubevirt-console-plugin-service 19445:9443
start_pf gitops-plugin               -n openshift-gitops port-forward svc/gitops-plugin 19447:9001
start_pf forklift-console-plugin     -n openshift-mtv port-forward svc/forklift-ui-plugin 19446:9443
start_pf kubevirt-apiserver-proxy    -n openshift-cnv port-forward svc/kubevirt-apiserver-proxy-service 18080:8080
start_pf forklift-inventory          -n openshift-mtv port-forward svc/forklift-inventory 18443:8443
start_token_refresh
start_connectivity_watchdog
sleep 3

export BRIDGE_PERSPECTIVES='[{"id":"dev","visibility":{"state":"Disabled"}}]'
export BRIDGE_PLUGINS="networking-console-plugin=https://127.0.0.1:19443/,monitoring-plugin=https://127.0.0.1:19444/,mce=https://127.0.0.1:19300/plugin/,acm=https://127.0.0.1:19301/plugin/,kubevirt-plugin=https://127.0.0.1:19445/,gitops-plugin=https://127.0.0.1:19447/,forklift-console-plugin=https://127.0.0.1:19446/"
export BRIDGE_PLUGINS_ORDER="networking-console-plugin,monitoring-plugin,mce,acm,kubevirt-plugin,gitops-plugin,forklift-console-plugin"
export BRIDGE_I18N_NAMESPACES="plugin__networking-console-plugin,plugin__monitoring-plugin,plugin__mce,plugin__acm,plugin__forklift-console-plugin,plugin__kubevirt-plugin,plugin__gitops-plugin"
export BRIDGE_PLUGIN_PROXY='{"services":[{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/mce/console/","endpoint":"https://127.0.0.1:19300"},{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/acm/console/","endpoint":"https://127.0.0.1:19301"},{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/kubevirt-plugin/kubevirt-apiserver-proxy/","endpoint":"https://127.0.0.1:18080"},{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/forklift-console-plugin/forklift-inventory/","endpoint":"https://127.0.0.1:18443"}]}'
export BRIDGE_RELEASE_VERSION="${BRIDGE_RELEASE_VERSION:-$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo 4.21.0)}"

echo ""
echo "Starting bridge with cluster plugins and perspective customization..."
echo "  Dev perspective: Disabled (matches Console operator)"
echo "  Plugins: ${BRIDGE_PLUGINS_ORDER}"
echo "  Console URL: http://localhost:9000"
echo "  Auto-recovery: port-forwards + token refresh + browser reload on reconnect"
echo ""

./bin/bridge &
BRIDGE_PID=$!
echo "$BRIDGE_PID" >"$BRIDGE_PID_FILE"
wait "$BRIDGE_PID"
