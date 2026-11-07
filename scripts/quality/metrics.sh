#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
atlas_compiler=$(xcrun --find swiftc)
atlas_host="$(dirname "$(dirname "$atlas_compiler")")/lib/swift/host"
[ -d "$atlas_host" ] || { echo 'Selected Xcode is missing SwiftSyntax host libraries.' >&2; exit 1; }
mkdir -p .build/quality
if [ ! -x .build/quality/metrics ] || [ scripts/quality/metrics.swift -nt .build/quality/metrics ]; then
    xcrun swiftc scripts/quality/metrics.swift -I "$atlas_host" -L "$atlas_host" -lSwiftSyntax -lSwiftParser \
        -Xlinker -rpath -Xlinker "$atlas_host" -o .build/quality/metrics
fi
exec .build/quality/metrics "$@"
