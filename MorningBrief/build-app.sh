#!/bin/bash
# Build MorningBrief.app bundle from the Swift package
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Robert Adams (9MJVJJ44N6)}"

echo "Building MorningBrief..."
swift build -c debug

APP_DIR="$SCRIPT_DIR/.build/MorningBrief.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp .build/arm64-apple-macosx/debug/MorningBrief "$MACOS/MorningBrief"

# Copy bundle resources — SPM's Bundle.module looks next to the executable (MacOS/)
BUNDLE_SRC=".build/arm64-apple-macosx/debug/MorningBrief_MorningBrief.bundle"
if [[ -d "$BUNDLE_SRC" ]]; then
  cp -R "$BUNDLE_SRC" "$MACOS/"
  # Add Info.plist so codesign accepts the nested bundle
  cat > "$MACOS/MorningBrief_MorningBrief.bundle/Info.plist" << 'BPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.morningbrief.app.resources</string>
    <key>CFBundleName</key>
    <string>MorningBrief Resources</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
</dict>
</plist>
BPLIST
fi

# Create entitlements
cat > "$SCRIPT_DIR/.build/MorningBrief.entitlements" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.morningbrief.app</string>
    <key>CFBundleName</key>
    <string>Morning Brief</string>
    <key>CFBundleExecutable</key>
    <string>MorningBrief</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

# Code sign (sign nested bundles first, then the app)
echo "Signing with: $SIGN_IDENTITY"
find "$APP_DIR" -name "*.bundle" -exec \
  codesign --force --sign "$SIGN_IDENTITY" {} \;
codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements "$SCRIPT_DIR/.build/MorningBrief.entitlements" \
  --options runtime \
  "$APP_DIR"

echo ""
codesign -dvv "$APP_DIR" 2>&1 | grep -E "Authority|Identifier|Signature"
echo ""
echo "Built: $APP_DIR"
echo "Run with: open $APP_DIR"
