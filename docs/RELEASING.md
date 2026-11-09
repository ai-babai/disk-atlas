---
type: Release Guide
description: Repeatable Developer ID signing, Apple notarization, stapling and verification for direct Disk Atlas distribution.
created: "2026-11-09"
---
# Signed releases outside the App Store

Local builds remain ad hoc by default. Official releases starting at 0.15.2 use
Developer ID Application, Hardened Runtime, secure timestamps and Apple notarization.
The signing key and app-specific password stay in the login Keychain; never export
or put them in arguments, environment variables, the repository or release assets.
The identity hash and Keychain **profile name** below are public configuration.

Use an unused patch/build number in Resources/Info.plist and AtlasCLI/Entrypoint.swift.
Run the shared quality gate before push. New releases never replace published assets.

## Build and sign

```sh
export ATLAS_SIGN_IDENTITY=0E91DEDE2D18F7641235D7DA72803668CD1DC290
atlas_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
atlas_release_dir="dist/release/$atlas_version"
scripts/release.sh --output "$atlas_release_dir"
atlas_app="$atlas_release_dir/Disk Atlas.app"
atlas_zip="$atlas_release_dir/Disk-Atlas-$atlas_version-universal.zip"
atlas_dmg="$atlas_release_dir/Disk-Atlas-$atlas_version-universal.dmg"
```

Identity: **Developer ID Application: Maksim Popkov (59Z5886M52)**.
`assemble` signs the embedded CLI first, then the app; `package` signs the DMG.
`--deep` is used only for verification. Existing entitlements are preserved when
signing executables. The current app needs no additional entitlements and is not
sandboxed; do not add JIT, library-validation exceptions or debugging entitlements.
The app has two statically linked Mach-O executables and no embedded frameworks.
If that bundle structure changes, review the inside-out signing order explicitly.

## Notarize and staple the app

```sh
xcrun notarytool submit "$atlas_zip" --keychain-profile personal-os-notary --wait
```

**Continue only when the status is Accepted.** An upload ID alone is not approval.
For failure details use `xcrun notarytool log SUBMISSION-ID --keychain-profile personal-os-notary`.
Do not disable Gatekeeper, remove quarantine, weaken trust or re-sign an accepted app.

```sh
xcrun stapler staple "$atlas_app"
xcrun stapler validate "$atlas_app"
python3 - "$atlas_release_dir" "$atlas_version" <<'PYTHON'
import sys
from pathlib import Path
from scripts.build import package

directory = Path(sys.argv[1]).resolve()
package(directory / "Disk Atlas.app", directory, sys.argv[2])
PYTHON
```

Repackaging includes the **stapled app** in both the ZIP and DMG without rebuilding
or re-signing it. The standalone CLI ZIP contains the same signed CLI approved as
nested code in the app. Apple does not support stapling raw command-line binaries;
use the app/DMG when a stapled container is required.

## Notarize the final DMG

```sh
xcrun notarytool submit "$atlas_dmg" --keychain-profile personal-os-notary --wait
```

Again, require **Accepted** before continuing:

```sh
xcrun stapler staple "$atlas_dmg"
xcrun stapler validate "$atlas_dmg"
codesign --verify --deep --strict --all-architectures "$atlas_app"
codesign --verify --strict --all-architectures "$atlas_app/Contents/MacOS/disk-atlas"
codesign --verify --strict "$atlas_dmg"
spctl --assess --type execute --verbose=4 "$atlas_app"
spctl --assess --type open --context context:primary-signature --verbose=4 "$atlas_dmg"
hdiutil verify "$atlas_dmg"
lipo -info "$atlas_app/Contents/MacOS/DiskAtlas"
lipo -info "$atlas_app/Contents/MacOS/disk-atlas"
(cd "$atlas_release_dir" && shasum -a 256 "Disk-Atlas-$atlas_version-universal.dmg" "Disk-Atlas-$atlas_version-universal.zip" "disk-atlas-cli-$atlas_version-universal.zip" > SHA256SUMS.txt)
```

Calculate checksums **after stapling**, since stapling changes the DMG. Mount the
final image read-only, validate its contained app/ticket, then quit the installed
app and install that release. Verify normal GUI launch and CLI on this Mac; do not
claim another-Mac or disconnected-machine testing without actually performing it.
Publish the new version's DMG, app ZIP, CLI ZIP and final checksum manifest only
after these checks. Verify anonymous downloads against the manifest.

Apple: [Developer ID](https://developer.apple.com/developer-id/),
[customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
