---
type: Security Policy
description: Reporting security issues and protecting private metadata in Disk Atlas.
created: "2026-11-07"
---
# Security

Report security issues through [GitHub private vulnerability reporting](https://github.com/ai-babai/disk-atlas/security/advisories/new). Include the app version,
macOS version and a minimal reproduction using synthetic paths and files.

You can also contact the maintainer privately via Telegram [@SkifMax](https://t.me/SkifMax) or email [wip.maks.craft@yandex.com](mailto:wip.maks.craft@yandex.com). English and Russian are welcome.

Do not attach a real `.atlas` snapshot, history archive, absolute personal paths or
file listings without reviewing their contents. Snapshots contain names, paths,
sizes and dates. Duplicate reports also contain copy relationships and content
digests. Ordinary scans read metadata only; duplicate checking reads contents
locally only after a separate explicit action. No file content is included in reports.

Only download release artifacts from this repository. Check `SHA256SUMS.txt`.
These releases are ad hoc signed and are not notarized by Apple; it does not carry
a verified Developer ID identity. See [Apple's opening guidance](https://support.apple.com/102445).

See [the architecture guide](docs/ARCHITECTURE.md) for the metadata/content-reading boundary,
local storage permissions and APFS accounting limitations.
