#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

atlas_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
atlas_release="dist/release"
atlas_app="$atlas_release/Disk Atlas.app"
atlas_cli_stage=$(mktemp -d "${TMPDIR:-/tmp}/disk-atlas-cli-release.XXXXXX")
atlas_stage=$(mktemp -d "${TMPDIR:-/tmp}/disk-atlas-release.XXXXXX")
trap 'rm -rf "$atlas_stage" "$atlas_cli_stage"' EXIT

swift build -c release --arch arm64
swift build -c release --arch x86_64
mkdir -p "$atlas_app/Contents/MacOS" "$atlas_app/Contents/Resources"
for atlas_binary in DiskAtlas disk-atlas; do
    lipo -create ".build/arm64-apple-macosx/release/$atlas_binary" ".build/x86_64-apple-macosx/release/$atlas_binary" \
        -output "$atlas_app/Contents/MacOS/$atlas_binary"
done
cp Resources/Info.plist "$atlas_app/Contents/Info.plist"
cp LICENSE "$atlas_app/Contents/Resources/LICENSE.txt"
cp -Rf Resources/ThirdParty "$atlas_app/Contents/Resources/"
swift scripts/icon.swift "$atlas_app/Contents/Resources"
codesign --force --deep --sign - "$atlas_app"
codesign --verify --deep --strict "$atlas_app"
ditto "$atlas_app" "$atlas_stage/Disk Atlas.app"
ln -s /Applications "$atlas_stage/Applications"
cp docs/INSTALL.txt "$atlas_stage/INSTALL.txt"
cp LICENSE "$atlas_stage/LICENSE.txt"

atlas_name="Disk-Atlas-${atlas_version}-universal"
hdiutil create -volname "Disk Atlas" -srcfolder "$atlas_stage" -format UDZO -ov "$atlas_release/$atlas_name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$atlas_app" "$atlas_release/$atlas_name.zip"
cp "$atlas_app/Contents/MacOS/disk-atlas" "$atlas_cli_stage/disk-atlas"
cp LICENSE "$atlas_cli_stage/LICENSE.txt"
cp -Rf Resources/ThirdParty "$atlas_cli_stage/ThirdParty"
cp docs/CLI-INSTALL.txt "$atlas_cli_stage/README.txt"
ditto -c -k "$atlas_cli_stage" "$atlas_release/disk-atlas-cli-${atlas_version}-universal.zip"
(
    cd "$atlas_release"
    shasum -a 256 "$atlas_name.dmg" "$atlas_name.zip" "disk-atlas-cli-${atlas_version}-universal.zip" > SHA256SUMS.txt
)
echo "Universal release: $(pwd)/$atlas_release"
