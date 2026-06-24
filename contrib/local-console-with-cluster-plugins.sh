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
# Stop cleanly:
#   ./contrib/local-console-stop.sh
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
PID_FILE="${STATE_DIR}/pids"
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

# Stale port-forwards from a prior session block new ones and break plugin loading.
# Do not clear 9001/9002 — those are local webpack dev servers for plugins.
PLUGIN_PORTS=(19443 19444 19445 19446 19447 19448 19300 19301 18080 18443)
for port in "${PLUGIN_PORTS[@]}"; do
  pids=$(lsof -ti ":$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  Clearing stale listener on port $port"
    kill $pids 2>/dev/null || true
  fi
done
if lsof -ti :9000 >/dev/null 2>&1; then
  echo "  Stopping existing bridge on port 9000"
  lsof -ti :9000 | xargs kill 2>/dev/null || true
  sleep 1
fi

PF_PIDS=()
start_pf() {
  local label=$1
  shift
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

start_pf_if_svc_exists() {
  local label=$1 ns=$2 svc=$3
  shift 3
  if oc get svc -n "$ns" "$svc" >/dev/null 2>&1; then
    start_pf "$label" -n "$ns" port-forward "svc/$svc" "$@"
    return 0
  fi
  echo "  SKIP $label (service $svc not found in $ns)" >&2
  return 1
}

wait_for_url() {
  local label=$1 url=$2
  local insecure=${3:-false}
  local curl_args=(-sf --max-time 3)
  if [ "$insecure" = true ]; then
    curl_args=(-skf --max-time 3)
  fi
  for _ in 1 2 3 4 5 6 7 8; do
    if curl "${curl_args[@]}" "$url" >/dev/null 2>&1; then
      echo "  OK $label"
      return 0
    fi
    sleep 1
  done
  echo "  FAIL $label ($url)" >&2
  return 1
}

start_token_refresh() {
  if [ "${BRIDGE_USE_LONG_LIVED_TOKEN:-}" = "1" ]; then
    echo "  using long-lived token from examples/token"
    return 0
  fi
  if [ -z "${BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE:-}" ]; then
    return 0
  fi
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
  rm -f "$BRIDGE_PID_FILE" "$PID_FILE"
  for pid in "${PF_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
    pkill -P "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

echo "Reading Console operator configuration from cluster..."
CLUSTER_PLUGINS=$(oc get console.operator cluster -o jsonpath='{range .spec.plugins[*]}{.name}{"\n"}{end}' 2>/dev/null || true)
if [ -z "$CLUSTER_PLUGINS" ]; then
  CLUSTER_PLUGINS=$'networking-console-plugin\nmonitoring-plugin\nmce\nacm\nkubevirt-plugin\nforklift-console-plugin\ngitops-plugin\nnmstate-console-plugin'
fi
CLUSTER_PERSPECTIVES=$(oc get console.operator cluster -o jsonpath='{.spec.customization.perspectives}' 2>/dev/null || true)
if [ -n "$CLUSTER_PERSPECTIVES" ] && [ "$CLUSTER_PERSPECTIVES" != "null" ]; then
  export BRIDGE_PERSPECTIVES="$CLUSTER_PERSPECTIVES"
else
  export BRIDGE_PERSPECTIVES='[{"id":"dev","visibility":{"state":"Disabled"}}]'
fi

plugin_enabled() {
  echo "$CLUSTER_PLUGINS" | grep -qx "$1"
}

echo "Starting plugin port-forwards..."
NETWORKING_PLUGIN_URL="https://127.0.0.1:19443/"
NETWORKING_OK=false
if plugin_enabled networking-console-plugin; then
  if curl -sf "http://localhost:9001/plugin-manifest.json" >/dev/null 2>&1; then
    NETWORKING_PLUGIN_URL="http://localhost:9001/"
    NETWORKING_OK=true
    echo "  Using local networking-console-plugin webpack dev server (port 9001)"
  elif start_pf_if_svc_exists networking-console-plugin openshift-network-console networking-console-plugin 19443:9443; then
    NETWORKING_OK=true
  fi
fi

MONITORING_OK=false
if plugin_enabled monitoring-plugin; then
  start_pf_if_svc_exists monitoring-plugin openshift-monitoring monitoring-plugin 19444:9443 && MONITORING_OK=true
fi

MCE_OK=false
if plugin_enabled mce; then
  start_pf_if_svc_exists mce multicluster-engine console-mce-console 19300:3000 && MCE_OK=true
fi

ACM_OK=false
if plugin_enabled acm; then
  start_pf_if_svc_exists acm open-cluster-management console-chart-console-v2 19301:3000 && ACM_OK=true
fi

KUBEVIRT_OK=false
KUBEVIRT_PLUGIN_URL="https://127.0.0.1:19445/"
if plugin_enabled kubevirt-plugin; then
  if curl -sf "http://localhost:9002/plugin-manifest.json" >/dev/null 2>&1; then
    KUBEVIRT_PLUGIN_URL="http://localhost:9002/"
    KUBEVIRT_OK=true
    echo "  Using local kubevirt-plugin webpack dev server (port 9002)"
  elif start_pf_if_svc_exists kubevirt-plugin openshift-cnv kubevirt-console-plugin-service 19445:9443; then
    KUBEVIRT_OK=true
  fi
  start_pf_if_svc_exists kubevirt-apiserver-proxy openshift-cnv kubevirt-apiserver-proxy-service 18080:8080 || true
fi

GITOPS_OK=false
if plugin_enabled gitops-plugin; then
  start_pf_if_svc_exists gitops-plugin openshift-gitops gitops-plugin 19447:9001 && GITOPS_OK=true
fi

FORKLIFT_OK=false
if plugin_enabled forklift-console-plugin; then
  start_pf_if_svc_exists forklift-console-plugin openshift-mtv forklift-ui-plugin 19446:9443 && FORKLIFT_OK=true
  start_pf_if_svc_exists forklift-inventory openshift-mtv forklift-inventory 18443:8443 || true
fi

NMSTATE_OK=false
if plugin_enabled nmstate-console-plugin; then
  start_pf_if_svc_exists nmstate-console-plugin openshift-nmstate nmstate-console-plugin 19448:9443 && NMSTATE_OK=true
fi

start_token_refresh
start_connectivity_watchdog
sleep 3

echo "Verifying plugin endpoints..."
FAILED=0
if plugin_enabled networking-console-plugin && [ "$NETWORKING_OK" = true ]; then
  if [[ "$NETWORKING_PLUGIN_URL" == http://* ]]; then
    wait_for_url networking-console-plugin "${NETWORKING_PLUGIN_URL}plugin-manifest.json" || FAILED=$((FAILED + 1))
  else
    wait_for_url networking-console-plugin "${NETWORKING_PLUGIN_URL}plugin-manifest.json" true || FAILED=$((FAILED + 1))
  fi
fi
if plugin_enabled monitoring-plugin && [ "$MONITORING_OK" = true ]; then
  wait_for_url monitoring-plugin "https://127.0.0.1:19444/plugin-manifest.json" true || FAILED=$((FAILED + 1))
fi
if plugin_enabled mce && [ "$MCE_OK" = true ]; then
  wait_for_url mce "https://127.0.0.1:19300/plugin/plugin-manifest.json" true || FAILED=$((FAILED + 1))
fi
if plugin_enabled acm && [ "$ACM_OK" = true ]; then
  wait_for_url acm "https://127.0.0.1:19301/plugin/plugin-manifest.json" true || FAILED=$((FAILED + 1))
fi
if plugin_enabled kubevirt-plugin && [ "$KUBEVIRT_OK" = true ]; then
  if [[ "$KUBEVIRT_PLUGIN_URL" == http://* ]]; then
    wait_for_url kubevirt-plugin "${KUBEVIRT_PLUGIN_URL}plugin-manifest.json" || FAILED=$((FAILED + 1))
  else
    wait_for_url kubevirt-plugin "${KUBEVIRT_PLUGIN_URL}plugin-manifest.json" true || FAILED=$((FAILED + 1))
  fi
fi
if plugin_enabled gitops-plugin && [ "$GITOPS_OK" = true ]; then
  wait_for_url gitops-plugin "https://127.0.0.1:19447/plugin-manifest.json" true || FAILED=$((FAILED + 1))
fi
if plugin_enabled forklift-console-plugin && [ "$FORKLIFT_OK" = true ]; then
  wait_for_url forklift-console-plugin "https://127.0.0.1:19446/plugin-manifest.json" true || FAILED=$((FAILED + 1))
fi
if plugin_enabled nmstate-console-plugin && [ "$NMSTATE_OK" = true ]; then
  wait_for_url nmstate-console-plugin "https://127.0.0.1:19448/plugin-manifest.json" true || FAILED=$((FAILED + 1))
fi

if [ "$FAILED" -gt 0 ]; then
  echo "" >&2
  echo "ERROR: $FAILED cluster plugin(s) failed health checks." >&2
  echo "Fix port-forwards before starting bridge, or run: ./contrib/local-console-stop.sh" >&2
  exit 1
fi

BRIDGE_PLUGINS_PARTS=()
BRIDGE_PLUGINS_ORDER_PARTS=()
BRIDGE_I18N_PARTS=()

add_plugin() {
  local name=$1 url=$2
  BRIDGE_PLUGINS_PARTS+=("${name}=${url}")
  BRIDGE_PLUGINS_ORDER_PARTS+=("$name")
  BRIDGE_I18N_PARTS+=("plugin__${name}")
}

while IFS= read -r plugin; do
  [ -z "$plugin" ] && continue
  case "$plugin" in
    networking-console-plugin)
      [ "$NETWORKING_OK" = true ] && add_plugin networking-console-plugin "$NETWORKING_PLUGIN_URL"
      ;;
    monitoring-plugin)
      [ "$MONITORING_OK" = true ] && add_plugin monitoring-plugin "https://127.0.0.1:19444/"
      ;;
    mce)
      [ "$MCE_OK" = true ] && add_plugin mce "https://127.0.0.1:19300/plugin/"
      ;;
    acm)
      [ "$ACM_OK" = true ] && add_plugin acm "https://127.0.0.1:19301/plugin/"
      ;;
    kubevirt-plugin)
      [ "$KUBEVIRT_OK" = true ] && add_plugin kubevirt-plugin "$KUBEVIRT_PLUGIN_URL"
      ;;
    gitops-plugin)
      [ "$GITOPS_OK" = true ] && add_plugin gitops-plugin "https://127.0.0.1:19447/"
      ;;
    forklift-console-plugin)
      [ "$FORKLIFT_OK" = true ] && add_plugin forklift-console-plugin "https://127.0.0.1:19446/"
      ;;
    nmstate-console-plugin)
      [ "$NMSTATE_OK" = true ] && add_plugin nmstate-console-plugin "https://127.0.0.1:19448/"
      ;;
    *)
      echo "  NOTE: cluster plugin '$plugin' is not configured for local port-forward" >&2
      ;;
  esac
done <<< "$CLUSTER_PLUGINS"

export BRIDGE_PLUGINS
BRIDGE_PLUGINS=$(IFS=,; echo "${BRIDGE_PLUGINS_PARTS[*]}")
export BRIDGE_PLUGINS_ORDER
BRIDGE_PLUGINS_ORDER=$(IFS=,; echo "${BRIDGE_PLUGINS_ORDER_PARTS[*]}")
export BRIDGE_I18N_NAMESPACES
BRIDGE_I18N_NAMESPACES=$(IFS=,; echo "${BRIDGE_I18N_PARTS[*]}")

PROXY_SERVICES=()
if [ "$MCE_OK" = true ]; then
  PROXY_SERVICES+=('{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/mce/console/","endpoint":"https://127.0.0.1:19300"}')
fi
if [ "$ACM_OK" = true ]; then
  PROXY_SERVICES+=('{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/acm/console/","endpoint":"https://127.0.0.1:19301"}')
fi
if [ "$KUBEVIRT_OK" = true ]; then
  PROXY_SERVICES+=('{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/kubevirt-plugin/kubevirt-apiserver-proxy/","endpoint":"https://127.0.0.1:18080"}')
fi
if [ "$FORKLIFT_OK" = true ]; then
  PROXY_SERVICES+=('{"authorize":true,"caCertificate":"","consoleAPIPath":"/api/proxy/plugin/forklift-console-plugin/forklift-inventory/","endpoint":"https://127.0.0.1:18443"}')
fi
export BRIDGE_PLUGIN_PROXY="{\"services\":[$(IFS=,; echo "${PROXY_SERVICES[*]}")]}"

export BRIDGE_RELEASE_VERSION="${BRIDGE_RELEASE_VERSION:-$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo 4.21.0)}"

{
  echo "# local console session — run ./contrib/local-console-stop.sh to clean up"
  for pid in "${PF_PIDS[@]}"; do
    echo "pf $pid"
  done
} > "$PID_FILE"

echo ""
echo "Starting bridge with cluster plugins and perspective customization..."
echo "  Perspectives: ${BRIDGE_PERSPECTIVES}"
echo "  Plugins: ${BRIDGE_PLUGINS_ORDER}"
echo "  Console URL: http://localhost:9000"
echo "  Auto-recovery: port-forwards + token refresh + browser reload on reconnect"
echo "  Stop with: ./contrib/local-console-stop.sh"
echo ""

./bin/bridge &
BRIDGE_PID=$!
echo "$BRIDGE_PID" >"$BRIDGE_PID_FILE"
echo "bridge $BRIDGE_PID" >> "$PID_FILE"
wait "$BRIDGE_PID"
