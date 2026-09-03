#!/bin/bash
# Builds GoveeKettle.app — a proper macOS app bundle (menu bar only, no Dock icon)
# so it can be added as a Login Item.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="GoveeKettle"
APP_DIR="dist/${APP_NAME}.app"
BIN_NAME="GoveeKettle"

swift build -c release

rm -rf "dist"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/${BIN_NAME}" "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp ".env" "$APP_DIR/Contents/MacOS/.env"
cp "Scripts/icon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.patrickgardella.govee-kettle</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

echo "Built: $APP_DIR"
echo "Move it to /Applications, then add as a Login Item."
