#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="dist/Disk Atlas.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/DiskAtlas .build/release/disk-atlas "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
swift scripts/icon.swift "$app/Contents/Resources"
codesign --force --deep --sign - "$app"
if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    ditto "$app" "$HOME/Applications/Disk Atlas.app"
    mkdir -p "$HOME/.local/bin"
    if [[ ! -e "$HOME/.local/bin/disk-atlas" && ! -L "$HOME/.local/bin/disk-atlas" ]]; then
        ln -s "$HOME/Applications/Disk Atlas.app/Contents/MacOS/disk-atlas" "$HOME/.local/bin/disk-atlas"
    fi
    echo "Installed: $HOME/Applications/Disk Atlas.app"
fi
echo "Built: $(pwd)/$app"
