#!/usr/bin/env bash
#
# Keep local OpenShift console healthy across network outages.
#
# - Waits for cluster access when offline
# - Starts yarn dev and bridge with cluster plugins when needed
# - On reconnect: refreshes API token, reloads browser tabs (plugins re-init)
#
# Usage (repo root):
#   ./contrib/local-console-daemon.sh          # run in a terminal or tmux
#   ./contrib/install-local-console-autostart.sh  # macOS login autostart
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=contrib/local-console-lib.sh
source "$ROOT_DIR/contrib/local-console-lib.sh"

STATE_DIR="${ROOT_DIR}/.local-console"
PID_FILE="${STATE_DIR}/daemon.pid"
BRIDGE_PID_FILE="${STATE_DIR}/bridge.pid"
LOG_FILE="${STATE_DIR}/daemon.log"
POLL_INTERVAL=${LOCAL_CONSOLE_POLL_INTERVAL:-30}

mkdir -p "$STATE_DIR"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Local console daemon already running (pid $(cat "$PID_FILE"))." >&2
  echo "Stop it with: kill \$(cat $PID_FILE)" >&2
  exit 1
fi

echo $$ >"$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT INT TERM

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

start_bridge_stack() {
  if [ -f "${STATE_DIR}/stack.pid" ] && kill -0 "$(cat "${STATE_DIR}/stack.pid")" 2>/dev/null; then
    return 0
  fi
  log "Starting bridge + plugin port-forwards..."
  # Run stack in background; it writes bridge pid and manages supervisors.
  "$ROOT_DIR/contrib/local-console-with-cluster-plugins.sh" --managed-by-daemon >>"$LOG_FILE" 2>&1 &
  local stack_pid=$!
  echo "$stack_pid" >"${STATE_DIR}/stack.pid"
  sleep 5
  if [ -f "$BRIDGE_PID_FILE" ] && kill -0 "$(cat "$BRIDGE_PID_FILE")" 2>/dev/null; then
    log "Bridge running (pid $(cat "$BRIDGE_PID_FILE"))"
    return 0
  fi
  log "Bridge stack failed to start — see $LOG_FILE"
  return 1
}

stop_bridge_stack() {
  if [ -f "${STATE_DIR}/stack.pid" ]; then
    local stack_pid
    stack_pid=$(cat "${STATE_DIR}/stack.pid")
    kill "$stack_pid" 2>/dev/null || true
    pkill -P "$stack_pid" 2>/dev/null || true
    rm -f "${STATE_DIR}/stack.pid" "$BRIDGE_PID_FILE"
  fi
}

recover_after_reconnect() {
  log "Cluster back online — recovering local console..."
  local_console_refresh_token || log "Token refresh skipped (re-login with oc if API stays broken)"
  if ! local_console_bridge_running; then
    stop_bridge_stack
    local_console_ensure_yarn_dev "$ROOT_DIR" || true
    start_bridge_stack || true
  else
  sleep 5
  fi
  local_console_reload_browser
  local_console_notify "Console reconnected — browser tabs reloaded"
}

cluster_was_offline=false

log "Local console daemon started (poll every ${POLL_INTERVAL}s)"
log "Logs: $LOG_FILE"

while true; do
  if local_console_cluster_reachable; then
    if [ "$cluster_was_offline" = true ]; then
      recover_after_reconnect
      cluster_was_offline=false
    elif ! local_console_bridge_running; then
      local_console_ensure_yarn_dev "$ROOT_DIR" || true
      start_bridge_stack || true
    fi
  else
    if [ "$cluster_was_offline" = false ]; then
      log "Cluster unreachable — waiting for network / oc login..."
      cluster_was_offline=true
    fi
  fi
  sleep "$POLL_INTERVAL"
done
