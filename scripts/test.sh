#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), the
# Swift Testing framework ships but is not on the default search path, so add it.
set -euo pipefail
cd "${0:A:h}/.."

if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  libs=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  exec swift test \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$libs" "$@"
fi
exec swift test "$@"
