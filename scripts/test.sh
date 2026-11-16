#!/bin/bash
# Runs the unit tests. Works with full Xcode (CI) and with only the Command Line Tools,
# where the Swift Testing framework lives outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")/.."

flags=()
if ! xcodebuild -version >/dev/null 2>&1; then
    dev="$(xcode-select -p)/Library/Developer"
    flags=(-Xswiftc -F -Xswiftc "$dev/Frameworks"
           -Xlinker -F -Xlinker "$dev/Frameworks"
           -Xlinker -rpath -Xlinker "$dev/Frameworks"
           -Xlinker -rpath -Xlinker "$dev/usr/lib")
fi

swift test ${flags[@]+"${flags[@]}"} "$@"
