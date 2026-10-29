#!/bin/bash
# Builds AudioBatch.app from App.swift. Needs Xcode Command Line Tools (xcode-select --install).
set -e
cd "$(dirname "$0")"
APP="AudioBatch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library -swift-version 5 -O App.swift -o "$APP/Contents/MacOS/AudioBatch"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>AudioBatch</string>
  <key>CFBundleIdentifier</key><string>local.audiobatch</string>
  <key>CFBundleName</key><string>AudioBatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Built $APP"
open "$APP"
