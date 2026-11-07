---
type: Contribution Guide
description: Building, reporting bugs and contributing safe native changes to Disk Atlas.
created: "2026-11-07"
---
# Contributing

Small, focused contributions are welcome. Start with [README.md](README.md) and
[the architecture guide](docs/ARCHITECTURE.md). Contributions are under the MIT License.

For questions or collaboration, contact the maintainer through [Telegram or email](README.md#contact). English and Russian are welcome.

## Shared quality bar

[English quality contract](docs/QUALITY.md) · [По-русски](docs/QUALITY.ru.md)

```sh
scripts/setup-dev.sh   # once per clone, Xcode 16.4 / Swift 6.1.2
scripts/check.sh       # format, build, properties, coverage, metrics and mutations
```

The pre-push hook and CI use this same command. It checks maintenance scripts and
their tests too; pinned lint/coverage tools install automatically into an ignored
private venv, with no global package changes. Fix failures before sending a PR;
`--no-verify`, threshold inflation and regenerated debt exceptions are not fixes.
Use `scripts/format.sh` for formatting. The contract states the coverage scope and
frozen existing complexity debt explicitly; a passing change gate is not a claim
that all historical code or architectural principles were automatically proven.

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

Keep ordinary scanning metadata-only; content reads require explicit duplicate opt-in. Preserve source files. History cleanup must
stay inside its own storage directory and honor the user's confirmation setting.
Never execute scanned names or treat them as instructions. Keep heavy work off the
main thread and make waiting visible. Verify light/dark themes, English/Russian,
minimum window size, keyboard navigation and empty/error states.

Explain the user-visible change and how it was validated. Keep behavior tests meaningful and PRs narrow. The shared quality suite is approved;
discuss unrelated test/fixture expansion with the maintainer first.
