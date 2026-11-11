#!/bin/zsh
set -euo pipefail
BERTH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BERTH_ROOT"
./scripts/build-app.sh
BERTH_VERSION="$(<VERSION)"
BERTH_ARCH="$(uname -m)"
BERTH_NAME="Berth-$BERTH_VERSION-macos-$BERTH_ARCH"
BERTH_STAGE="$(mktemp -d "$BERTH_ROOT/.build/packaging/dmg.XXXXXX")"
trap 'rm -rf "$BERTH_STAGE"' EXIT
ditto "dist/Berth.app" "$BERTH_STAGE/Berth.app"
ln -s /Applications "$BERTH_STAGE/Applications"
ditto -c -k --sequesterRsrc --keepParent "dist/Berth.app" "dist/$BERTH_NAME.zip"
hdiutil create -volname "Berth" -srcfolder "$BERTH_STAGE" -ov -format UDZO "dist/$BERTH_NAME.dmg"
cd dist
shasum -a 256 "$BERTH_NAME.zip" "$BERTH_NAME.dmg" > "$BERTH_NAME.sha256"
print "Packaged: $BERTH_NAME"
