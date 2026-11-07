---
type: Changelog
description: User-visible changes and release boundaries for Disk Atlas.
created: "2026-11-07"
---
# Changelog

## 0.2.2 — 2026-11-07

- Move language selection to one compact toolbar menu, available on the start screen and with sidebars hidden.
- Remove duplicate language controls from the sidebar and welcome content.

## 0.2.1 — 2026-11-07

- Align history icons, titles, snapshot sizes and delete buttons on a shared top row.
- Align the snapshot column heading and tighten recent-scan spacing.
- Keep compact history titles readable and table cells aligned after resizing.
- Make each file-type row clickable across its label, size and bar, with hover feedback.
- Select multiple file types together, with checkmarks, a compact count and one-step reset.

## 0.2.0 — 2026-11-07

- Show the estimated uncompressed snapshot size during scanning and exact compressed size after saving.
- Show snapshot sizes and visible deletion buttons in the sidebar and directly on the start screen.
- Show total history storage in the history window.
- Delete individual scans or clear history together with app-owned metadata.
- Confirm deletion, optionally remember “Don’t ask again”, and allow confirmations to be re-enabled.
- Preserve source files and user exports; never recursively delete directories during history cleanup.
- Keep file columns within the available width when resizing sidebars.
- Publish the project under the MIT License with public downloads.

## 0.1.0 — 2026-11-07

First early access release for macOS 14+.

- Native treemap, virtualized file list, scoped search, type filters and inspector.
- Choose multiple folders before scanning; drag and drop and common locations.
- Allocated and logical sizes, creation and modification dates, Finder reveal.
- Persistent compressed scan history with compact rows and explicit loading stages.
- Resizable and collapsible sidebars, compact toolbar, light/dark themes, English/Russian UI.
- Shared metadata-only core for GUI, CLI and MCP; validated portable `.atlas` snapshots.
- Universal Apple Silicon/Intel DMG and ZIP, ad hoc signed, with SHA-256 checksums.

This build is not notarized by Apple. APFS allocated blocks are not guaranteed
reclaimable space. Large snapshots still take time and memory to decode and index.
