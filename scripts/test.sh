#!/bin/zsh
set -euo pipefail
BERTH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BERTH_ROOT"
# Some Command Line Tools versions include Testing without registering its macro plugin.
BERTH_SWIFT_BIN="$(dirname "$(xcrun --find swift)")"
BERTH_TESTING_PLUGIN="$BERTH_SWIFT_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$BERTH_TESTING_PLUGIN" ]]; then
    swift test -Xswiftc -load-plugin-library -Xswiftc "$BERTH_TESTING_PLUGIN"
else
    swift test
fi
