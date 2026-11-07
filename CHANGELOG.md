---
type: Changelog
description: User-visible changes and release boundaries for Disk Atlas.
created: "2026-11-07"
---
# Changelog

## 0.5.0 — 2026-11-07

- Make CLI the primary agent interface: per-command help, version, generated command/effect discovery, selected doctor diagnostics, safe idempotent installation and shell completion.
- Read, query and export existing GUI history without rescanning; query snapshots by folder, name, type, metric and sort order using bounded top-K results.
- Return versioned JSON automatically in pipes, bounded DTOs and explicit pages; distinguish usage, missing, partial and interrupted results. Keep data on stdout, diagnostics/progress on stderr, and add animated terminal activity and cooperative Ctrl-C/SIGTERM stop.
- Keep duplicate content reads opt-in; page saved report groups/files without rereading contents. Preserve the existing MCP tools.
- Add CLI process behavior tests to the shared gate, pin Apple's Swift Argument Parser, and reduce frozen CLI complexity debt by removing/refactoring old parsers.
- Make the For agents sheet CLI-first, publish EN/RU guides, and ship a standalone universal CLI ZIP with third-party notices.

## 0.4.0 — 2026-11-07

- Smooth native sidebar/inspector transitions preserve dragged widths and honor Reduce Motion.
- Isolate map invalidation: only the selected branch repaints; progress updates leave the map alone. Single clicks no longer wait for a potential double click.
- Select duplicate copies for recoverable Trash moves, with row/group actions, a mandatory full-path review, explicit remaining/all-selected indicators, cancellable background byte/identity revalidation, partial-failure reporting and updated saved results.
- Add clickable duplicate counts to the overview and inspector, scoped folder results, and a Size info explanation. Keep sorting in table headings.
- Add selection/full-group, scope, report-reconciliation and content-revalidation tests; reduce frozen complexity debt from 27 to 20 without relaxing thresholds.

## 0.3.2 — 2026-11-07

- Sort duplicate groups by repeated bytes, copy size, copy count or name, with reversible headings and background preparation.
- Replace the ambiguous ellipsis with a drive icon and Size menu.
- Add one contributor quality command, opt-in pre-push hook and matching pinned-toolchain CI.
- Add behavior/property tests, LLVM changed-Core coverage/CRAP checks, structural complexity and target/layer dependency checks, selected mutation tests and explicit frozen legacy debt.
- Apply consistent Swift formatting and split the modified duplicate-results body and MCP handler into cohesive responsibilities.

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
