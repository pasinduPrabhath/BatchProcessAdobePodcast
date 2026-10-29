#!/bin/bash
# Builds a universal (Apple Silicon + Intel) AudioBatch.app and packs it into a .dmg for distribution.
# Usage: bash package.sh [version]   e.g. bash package.sh 1.0.0
# Output: dist/AudioBatch-<version>.dmg
set -e
cd "$(dirname "$0")"
VERSION="${1:-1.0.0}"
VERSION="${VERSION#v}"
DIST="dist"
STAGE="$DIST/stage"
APP="$STAGE/AudioBatch.app"
DMG="$DIST/AudioBatch-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$APP/Contents/MacOS"

for ARCH in arm64 x86_64; do
  swiftc -parse-as-library -swift-version 5 -O -target "$ARCH-apple-macos12.0" \
    App.swift -o "$DIST/AudioBatch-$ARCH"
done
lipo -create "$DIST/AudioBatch-arm64" "$DIST/AudioBatch-x86_64" -output "$APP/Contents/MacOS/AudioBatch"
rm -f "$DIST/AudioBatch-arm64" "$DIST/AudioBatch-x86_64"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>AudioBatch</string>
  <key>CFBundleIdentifier</key><string>local.audiobatch</string>
  <key>CFBundleName</key><string>AudioBatch</string>
  <key>CFBundleDisplayName</key><string>AudioBatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad-hoc signature. Without a paid Apple Developer ID the app is not notarized,
# so users have to approve it once in Gatekeeper (see README).
codesign --force --deep --sign - "$APP"

ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AudioBatch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG"
