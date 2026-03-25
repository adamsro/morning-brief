#!/bin/bash
# Install morning-brief as a macOS launchd agent.
# This schedules daily execution at 9 AM (catches up on wake if missed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_NAME="com.mimicscribe.morning-brief"
PLIST_SRC="$SCRIPT_DIR/$PLIST_NAME.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
STATE_DIR="$HOME/.morning-brief"

echo "Installing morning-brief..."

# Check for config
if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
  echo ""
  echo "No config.sh found. Creating from example..."
  cp "$SCRIPT_DIR/config.example.sh" "$SCRIPT_DIR/config.sh"
  echo "Edit config.sh with your product and competitor details before running."
fi

# Make runner executable
chmod +x "$SCRIPT_DIR/morning-brief.sh"

# Create state directory
mkdir -p "$STATE_DIR"

# Generate plist with correct paths
sed -e "s|__INSTALL_DIR__|$SCRIPT_DIR|g" \
    -e "s|__HOME__|$HOME|g" \
    "$PLIST_SRC" > "$PLIST_DST"

# Unload if already loaded
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

# Load the agent
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

echo ""
echo "Installed! morning-brief will run daily at 9:00 AM."
echo "If your Mac is asleep at 9 AM, it will run on next wake."
echo ""
echo "  Manual run:    $SCRIPT_DIR/morning-brief.sh"
echo "  Force re-run:  $SCRIPT_DIR/morning-brief.sh --force"
echo "  Reports:       $SCRIPT_DIR/reports/"
echo "  Logs:          $STATE_DIR/morning-brief.log"
echo "  Uninstall:     $SCRIPT_DIR/uninstall.sh"
