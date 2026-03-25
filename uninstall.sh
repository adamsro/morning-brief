#!/bin/bash
# Uninstall morning-brief launchd agent.

set -euo pipefail

PLIST_NAME="com.mimicscribe.morning-brief"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "Uninstalling morning-brief..."

# Unload
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

# Remove plist
if [[ -f "$PLIST_DST" ]]; then
  rm "$PLIST_DST"
  echo "Removed $PLIST_DST"
fi

echo "Done. Reports and config are preserved."
echo "To remove everything: rm -rf ~/.morning-brief"
