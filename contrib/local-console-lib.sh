# shellcheck shell=bash
# Shared helpers for local OpenShift console dev (sourced, not executed).

local_console_cluster_reachable() {
  oc whoami >/dev/null 2>&1
}

local_console_refresh_token() {
  if [ "${BRIDGE_USE_LONG_LIVED_TOKEN:-}" = "1" ]; then
    return 0
  fi
  local token_file=${BRIDGE_K8S_MODE_OFF_CLUSTER_SERVICE_ACCOUNT_BEARER_TOKEN_FILE:-}
  if [ -z "$token_file" ]; then
    return 1
  fi
  local token
  token=$(oc whoami --show-token 2>/dev/null) || return 1
  [ -n "$token" ] && printf '%s' "$token" >"$token_file"
}

local_console_notify() {
  local message=$1
  echo "$message"
  if [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$message\" with title \"OpenShift Local Console\"" 2>/dev/null || true
  fi
}

# Hard-reload browser tabs on localhost:9000 so dynamic plugins re-initialize.
local_console_reload_browser() {
  if [ "$(uname -s)" != "Darwin" ] || ! command -v osascript >/dev/null 2>&1; then
    return 0
  fi
  osascript <<'APPLESCRIPT' 2>/dev/null || true
on reloadMatchingTabs(appName)
  tell application appName
    if not running then return
    repeat with w in windows
      repeat with t in tabs of w
        set tabUrl to URL of t
        if tabUrl starts with "http://localhost:9000" or tabUrl starts with "http://127.0.0.1:9000" then
          reload t
        end if
      end repeat
    end repeat
  end tell
end reloadMatchingTabs

reloadMatchingTabs("Google Chrome")
reloadMatchingTabs("Chromium")
reloadMatchingTabs("Arc")
reloadMatchingTabs("Microsoft Edge")
reloadMatchingTabs("Safari")
APPLESCRIPT
}

local_console_yarn_dev_running() {
  curl -s -o /dev/null --max-time 2 http://localhost:8080/ >/dev/null 2>&1
}

local_console_bridge_running() {
  curl -s -o /dev/null --max-time 2 http://localhost:9000/ >/dev/null 2>&1
}

local_console_ensure_yarn_dev() {
  local root_dir=$1
  if local_console_yarn_dev_running; then
    return 0
  fi
  echo "Starting yarn dev (webpack on :8080)..."
  (
    cd "$root_dir/frontend"
    exec yarn dev
  ) &
  local pid=$!
  local i=0
  while [ "$i" -lt 120 ]; do
    if local_console_yarn_dev_running; then
      echo "  yarn dev ready (pid $pid)"
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  echo "yarn dev did not become ready on :8080 within 4 minutes" >&2
  return 1
}
