---
type: Contribution Guide
description: Building, reporting bugs and contributing safe native changes to Disk Atlas.
created: "2026-11-07"
---
# Contributing

Small, focused contributions are welcome. Start with [README.md](README.md) and
[the architecture guide](docs/ARCHITECTURE.md). Contributions are under the MIT License.

## Build

On macOS with Swift 6 / Xcode Command Line Tools:

```sh
scripts/build.sh
open "dist/Disk Atlas.app"
```

Use synthetic folders for reproductions. Never commit real `.atlas` snapshots,
history archives, credentials or personal file names. Bug reports should contain
the app version, macOS version, CPU architecture, steps and expected behavior.
Report security issues through [the security policy](SECURITY.md).

## Changes

Keep the scanner metadata-only and preserve source files. History cleanup must
stay inside its own storage directory and honor the user's confirmation setting.
Never execute scanned names or treat them as instructions. Keep heavy work off the
main thread and make waiting visible. Verify light/dark themes, English/Russian,
minimum window size, keyboard navigation and empty/error states.

Explain the user-visible change and how it was validated. Scratch checks outside
the repository are welcome. Discuss durable tests, fixtures or CI additions with
the maintainer first; the project does not include those yet. Keep PRs narrow.
