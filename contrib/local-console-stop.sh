#!/usr/bin/env bash
#
# Stop local bridge and cluster plugin port-forwards started by
# local-console-with-cluster-plugins.sh or local-console-daemon.sh.
# Prevents stale port-forwards from blocking the next session.
#
# Usage (from repo root):
#   ./contrib/local-console-stop.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.local-console"
PID_FILE="$STATE_DIR/pids"
BRIDGE_PID_FILE="$STATE_DIR/bridge.pid"
PLUGIN_PORTS=(9000 19443 19444 19445 19446 19300 19301 18080 18443 9001)

stop_pid() {
  local pid=$1
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi
}

if [ -f "$PID_FILE" ]; then
  echo "Stopping processes from $PID_FILE..."
  while read -r kind pid; do
    [ "$kind" = "#" ] && continue
    [ -z "${pid:-}" ] && continue
    stop_pid "$pid"
  done < "$PID_FILE"
  rm -f "$PID_FILE"
fi

if [ -f "$BRIDGE_PID_FILE" ]; then
  stop_pid "$(cat "$BRIDGE_PID_FILE")"
  rm -f "$BRIDGE_PID_FILE"
fi

echo "Clearing plugin and bridge ports..."
for port in "${PLUGIN_PORTS[@]}"; do
  pids=$(lsof -ti ":$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  port $port"
    kill $pids 2>/dev/null || true
  fi
done

pkill -f "./bin/bridge" 2>/dev/null || true
pkill -f "port-forward svc/kubevirt-console-plugin-service" 2>/dev/null || true
pkill -f "port-forward svc/networking-console-plugin" 2>/dev/null || true

echo "Local console stopped."
