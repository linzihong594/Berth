#!/bin/zsh
set -euo pipefail
BERTH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BERTH_ROOT"
BERTH_VERSION="$(<VERSION)"
BERTH_NUMERIC_VERSION="${BERTH_VERSION%%-*}"
BERTH_BUNDLE_ID="${BERTH_BUNDLE_ID:-io.github.linzihong594.Berth}"
export MACOSX_DEPLOYMENT_TARGET=14.0
swift build -c release --product Berth
swift build -c release --product BerthServiceTool
swift build -c release --product BerthReadTool
BERTH_BIN="$(swift build -c release --show-bin-path)"
BERTH_APP="$BERTH_ROOT/dist/Berth.app"
mkdir -p "$BERTH_APP/Contents/MacOS" "$BERTH_APP/Contents/Resources"
cp "$BERTH_BIN/Berth" "$BERTH_APP/Contents/MacOS/Berth"
cp "$BERTH_BIN/BerthServiceTool" "$BERTH_APP/Contents/MacOS/BerthServiceTool"
cp "$BERTH_BIN/BerthReadTool" "$BERTH_APP/Contents/MacOS/BerthReadTool"
cat > "$BERTH_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Berth</string>
<key>CFBundleIdentifier</key><string>$BERTH_BUNDLE_ID</string>
<key>CFBundleName</key><string>Berth</string>
<key>CFBundleDisplayName</key><string>泊</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$BERTH_NUMERIC_VERSION</string>
<key>CFBundleVersion</key><string>$BERTH_NUMERIC_VERSION</string>
<key>BerthReleaseVersion</key><string>$BERTH_VERSION</string>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleIconFile</key><string>Berth</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
mkdir -p "$BERTH_ROOT/.build/packaging"
swift scripts/draw-icon.swift "$BERTH_ROOT/.build/packaging/Berth.iconset"
iconutil -c icns "$BERTH_ROOT/.build/packaging/Berth.iconset" -o "$BERTH_APP/Contents/Resources/Berth.icns"
# SwiftPM packages the core as a static library; no third-party runtime is needed.
codesign --force --sign - --timestamp=none "$BERTH_APP/Contents/MacOS/BerthServiceTool"
codesign --force --sign - --timestamp=none "$BERTH_APP/Contents/MacOS/BerthReadTool"
codesign --force --sign - --timestamp=none "$BERTH_APP"
codesign --verify --strict "$BERTH_APP"
print "Built: $BERTH_APP"
