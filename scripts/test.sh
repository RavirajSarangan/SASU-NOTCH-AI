#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed, SwiftPM
# doesn't find the swift-testing macro plugin by itself, so pass its path.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
    swift test "$@"
fi
