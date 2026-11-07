---
type: Changelog
description: User-visible changes and release boundaries for Disk Atlas.
created: "2026-11-07"
---
# Changelog

## 0.11.0 — 2026-11-08

- Make More areas selectable as temporary list groups, including nested map areas. Keep map scale, search and list mode; clear the group with its visible chip.
- Add independent Trash checkboxes, select-displayed control and per-row Trash actions to the ordinary file list. Review full paths, normalize folder/child overlap and revalidate current identities before recoverable native Trash moves.
- Keep the Trash action slot and duplicate selection indicators stable so checking items does not shift tables. Remove recurring result dimming during streamed duplicate sorting.
- Reconcile the current map/list and saved duplicate report after ordinary Trash; retain the historical scan archive until the user rescans.
- Share bounded list ordering across normal and group queries, with behavior tests and one fewer frozen complexity exception.

## 0.10.0 — 2026-11-08

- Keep the folder map visible in both list modes. Place Contents / Largest files directly above the table; switch only its rows while preserving folder, search, type filters and selection.
- Link list selection to the deepest visible map rectangle, with a containing-folder or grouped-area outline when the exact file is too small to draw. Keep the current map scale and navigation unchanged.
- Keep the map geometry stable across list-mode changes and adapt list controls to narrow windows.
- Add ancestry regression checks and verify nested selection geometry with an isolated native UI fixture.

## 0.9.1 — 2026-11-07

- Fix inspector resizing that could leave content outside the viewport. Pin each SwiftUI host to all four edges of an AppKit split-item container.
- Recalculate native table columns when its frame size changes, so dragging a sidebar does not leave the center table using a temporary narrow layout. Invalidate only on actual size changes to avoid repeated layout cycles.

## 0.9.0 — 2026-11-07

- Explain the two stages explicitly: calculate file sizes, then find duplicates in the background.
- Restore the cached workspace with Back or the same history entry after returning Home, preserving selection and filters.
- Make the right inspector genuinely resizable and retain pane widths across updates, collapse and Home. Put its toggle at the trailing toolbar edge.
- Replace the nested Size menu with a direct On disk / File size switch and info; adapt narrow layouts and keep table columns reachable by horizontal scrolling.
- Show startup volume name, free space and total capacity immediately from filesystem metadata without scanning files.
- Add volume metadata checks and retire one more frozen complexity exception without changing quality thresholds.

## 0.8.0 — 2026-11-07

- Reveal nested map selections in one temporary list row, without navigating or clearing filters; use AppKit’s native scroll destination so the first row is not hidden by the header.
- Underline Files with copies directly and remove the extra Open duplicates line. Make the sidebar brand return to the empty start screen, preserving history and background duplicate controls.
- Replace SHA-256 candidate fingerprints with vendored XXH3-128, retain byte/identity verification, partition fingerprint collisions, and skip full hashing for exactly two large sample survivors.
- Aggregate duplicate ancestor counts by distinct parent and defer unused type classification. Add cooperative cancellation to indexing and per-file report encoding; keep Stop enabled while saving and quit without indefinite background-write waits.
- Add regression checks for nested context rows, standard hash vectors/streaming, redundant read avoidance, collision partitioning and cancellation preserving a committed report. Retire five touched legacy complexity exceptions without changing thresholds.

## 0.7.0 — 2026-11-07

- Replace ambiguous disclosure arrows in overview/inspector duplicate metrics with explicit Open links.
- Scroll the file list to a selected map object after native layout, including nested search matches; preserve active search/type filters and honor Reduce Motion.
- Separate duplicate result filters from new-check options. Filter saved metadata by size/type without rereading contents or replacing the report; retain every peer of a matching group and show full filtered totals.
- Mark limited coverage honestly and offer an explicit new-check flow with metadata estimate before content-read opt-in. Cancelling its options preserves the existing report.
- Add cached-result history, boundary, cancellation and generated monotonic-filter checks; retire the native table update’s legacy complexity exception without expanding thresholds.

## 0.6.1 — 2026-11-07

- Align All groups and Options in a single, centered header action row with matching 28-point hit areas. Keep the return-to-all-groups action clear and prevent action labels from wrapping at narrow widths.

## 0.6.0 — 2026-11-07

- Add native Quick Look to folder contents, largest-file/search results and expanded duplicate groups: Space, row context menu, and a compact eye button for copies.
- Browse neighboring visible items inside the system preview panel; keep file-table selection and duplicate-row focus aligned, and close preview with Space/Escape or when leaving its list.
- Keep preview focus separate from Trash checkboxes and preserve their keyboard interaction. Read current file contents only after an explicit preview request; snapshots remain metadata-only.
- Extract file-list controls from presentation, removing one frozen complexity exception; the shared gate now also audits maintenance scripts and their tests.

## 0.5.2 — 2026-11-07

- Single-click a map rectangle to inspect the exact file or folder without changing the current directory, including nested folders and files.
- Keep navigation explicit through double-click, Explore folder and Open actions. A second click must hit the same entry; aggregate tiles stay inert.
- Keep direct-child selection/scrolling in the list and show the current list directory beside the inspector's type filter, separately from the selected item.

## 0.5.1 — 2026-11-07

- Combine scan metadata and duplicate activity into one stable 30-point status row, replacing the two stacked bars.
- Keep the duplicate count and result chevron in one clickable group; pause, stop and phase progress stay beside that job instead of separating its action across the window.
- Preserve snapshot storage size, partial/stopped state, accessibility labels and reduced-motion behavior; omit the repeated default notice and redundant current-folder title.

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
