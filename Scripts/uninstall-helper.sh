#!/bin/bash
set -euo pipefail

HELPER_LABEL="com.fujimotomasahiro.Fermata.Helper"
LEGACY_HELPER_LABEL="com.iccir.Fermata.Helper"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script requires administrator privileges. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

for label in "$HELPER_LABEL" "$LEGACY_HELPER_LABEL"; do
  launchctl bootout "system/${label}" 2>/dev/null || true
  rm -f "/Library/LaunchDaemons/${label}.plist"
  rm -f "/Library/PrivilegedHelperTools/${label}"
done

# Always restore normal lid-close sleep
pmset -a disablesleep 0

echo "Removed Fermata privileged helper(s) and restored SleepDisabled = 0."
