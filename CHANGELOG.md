---
type: Changelog
description: User-visible changes and release boundaries for Disk Atlas.
created: "2026-11-07"
---
# Changelog

## 0.3.2 — 2026-11-07

- Sort duplicate groups by repeated bytes, copy size, copy count or name, with reversible headings and background preparation.
- Replace the ambiguous ellipsis with a drive icon and Size menu.
- Add one contributor quality command, opt-in pre-push hook and matching pinned-toolchain CI.
- Add behavior/property tests, LLVM changed-Core coverage/CRAP checks, structural complexity and target/layer dependency checks, selected mutation tests and explicit frozen legacy debt.
- Apply consistent Swift formatting and split the modified duplicate-results body into cohesive sections.

## 0.3.1 — 2026-11-07

- Find duplicates at startup now reveals size options immediately and starts the background check after the map is ready, with no second Start action.
- Remove date restrictions from GUI duplicate checks; keep date filtering for map/list display and advanced CLI/MCP use.
- Make Filters a labeled button and move allocated/logical sizing into the display menu; On disk remains the default.
- Constrain inspector width so long names and paths wrap without stretching or clipping the panel.
- Select nested map rectangles accurately, reveal their parent and scroll to the selected row, including entries outside the first 1,000 results. Aggregate tiles remain inert.
- Persist results even when a small duplicate check finishes before its scan archive is ready.

## 0.3.0 — 2026-11-07

- Add an optional, explicitly started duplicate check with metadata-only preparation, read-volume/time estimates, background phases, pause/resume and stop.
- Prune by equal size and first/last samples, hash only survivors, then verify bytes; skip hard-link aliases, symlinks, special and cloud-only files, and reject changed files.
- Add compact duplicate groups, Finder reveal, report-only Keep marks, JSON export and file-list badges that open the exact group.
- Save duplicate reports with scan history, show their storage size and remove them when the history item is deleted.
- Add size-range presets, two-handle logarithmic sliders, exact bounds and modification-date criteria; commit costly changes after dragging ends.
- Add optional size/date view filters for both map and list; preserve original scan data.
- Separate Disk usage and Duplicates workspaces; keep Map / Largest files as local display modes and align sidebar selections.
- Add sortable native table headings and preserve the complete percentage column beside the inspector.
- Add explicit duplicate CLI/MCP actions; keep ordinary scanning metadata-only.
- Update English/Russian documentation and illustrative images.

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
