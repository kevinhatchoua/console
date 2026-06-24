#!/usr/bin/env bash
#
# Install a macOS LaunchAgent to run local-console-daemon.sh at login.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_LABEL="com.openshift.local-console"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
DAEMON_SCRIPT="${ROOT_DIR}/contrib/local-console-daemon.sh"
LOG_DIR="${ROOT_DIR}/.local-console"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "LaunchAgent install is only supported on macOS." >&2
  exit 1
fi

chmod +x "$DAEMON_SCRIPT"
mkdir -p "$LOG_DIR"

# Quote path for bash -lc (workspace path may contain spaces).
DAEMON_CMD="exec '${DAEMON_SCRIPT}'"

cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>${DAEMON_CMD}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${ROOT_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/launchd.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "Installed LaunchAgent: $PLIST_PATH"
echo "Daemon logs: $LOG_DIR/daemon.log"
echo ""
echo "Ensure you are logged into the cluster once (oc login) so the daemon can reach it."
echo "To remove: launchctl bootout gui/$(id -u) $PLIST_PATH && rm $PLIST_PATH"
