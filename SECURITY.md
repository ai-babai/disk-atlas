---
type: Security Policy
description: Reporting security issues and protecting private metadata in Disk Atlas.
created: "2026-11-07"
---
# Security

Report security issues privately to the repository owner. Include the app version,
macOS version and a minimal reproduction using synthetic paths and files.

Do not attach a real `.atlas` snapshot, history archive, absolute personal paths or
file listings without reviewing their contents. Snapshots contain names, paths,
sizes and dates even though file contents are not read.

Only download release artifacts from this private repository. Check `SHA256SUMS.txt`.
The 0.1.0 release is ad hoc signed and is not notarized by Apple; it does not carry
a verified Developer ID identity. See [Apple's opening guidance](https://support.apple.com/102445).

See [the architecture guide](docs/ARCHITECTURE.md) for the metadata-only boundary,
local storage permissions and APFS accounting limitations.
