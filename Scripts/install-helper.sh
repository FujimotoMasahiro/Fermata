#!/bin/bash
set -euo pipefail

HELPER_LABEL="com.fujimotomasahiro.Fermata.Helper"
LEGACY_HELPER_LABEL="com.iccir.Fermata.Helper"
APP_PATH="${1:-/Applications/Fermata.app}"
HELPER_SRC="${APP_PATH}/Contents/Library/LaunchServices/${HELPER_LABEL}"
HELPER_DST="/Library/PrivilegedHelperTools/${HELPER_LABEL}"
PLIST_DST="/Library/LaunchDaemons/${HELPER_LABEL}.plist"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script requires administrator privileges. Re-running with sudo..."
  exec sudo "$0" "$APP_PATH"
fi

if [[ ! -x "$HELPER_SRC" ]]; then
  echo "Error: Helper binary not found at: $HELPER_SRC"
  echo "Copy Fermata.app to /Applications first, or pass the path to Fermata.app as an argument:"
  echo "  sudo $0 /path/to/Fermata.app"
  exit 1
fi

# Stop and remove legacy helper if present to avoid conflicts
if [[ -f "/Library/LaunchDaemons/${LEGACY_HELPER_LABEL}.plist" ]]; then
  echo "Removing legacy helper (${LEGACY_HELPER_LABEL})..."
  launchctl bootout "system/${LEGACY_HELPER_LABEL}" 2>/dev/null || true
  rm -f "/Library/LaunchDaemons/${LEGACY_HELPER_LABEL}.plist"
  rm -f "/Library/PrivilegedHelperTools/${LEGACY_HELPER_LABEL}"
fi

# Stop existing version of this helper if running
launchctl bootout "system/${HELPER_LABEL}" 2>/dev/null || true

mkdir -p /Library/PrivilegedHelperTools
cp "$HELPER_SRC" "$HELPER_DST"
chown root:wheel "$HELPER_DST"
chmod 544 "$HELPER_DST"

cat > "$PLIST_DST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${HELPER_LABEL}</string>
	<key>MachServices</key>
	<dict>
		<key>${HELPER_LABEL}</key>
		<true/>
	</dict>
	<key>Program</key>
	<string>${HELPER_DST}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${HELPER_DST}</string>
	</array>
</dict>
</plist>
EOF

chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

launchctl bootstrap system "$PLIST_DST"

# Ensure normal sleep state on fresh install
pmset -a disablesleep 0

echo "Installed and started ${HELPER_LABEL} successfully."
echo "You can now launch ${APP_PATH}."
