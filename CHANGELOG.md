---
type: Changelog
description: User-visible changes and release boundaries for Disk Atlas.
created: "2026-11-07"
---
# Changelog

## 0.15.5 — 2026-11-12

- Use native outline rows and disclosure in Duplicates, matching Contents while keeping full paths and bounded rendering for large groups.
- Keep background activity in stable indicator slots, with cancellable map highlighting and no extra status panel shifting completed rows.
- Add local Help and a Report a Bug form with optional email, one manually chosen screenshot, and automatic app/macOS version details.
- Offer application-only diagnostics through an independent Settings switch, off by default; source paths and file names are excluded.
- Start in English unless a language choice has already been saved.

## 0.15.4 — 2026-11-11

- Keep file-type totals and expanded extensions tied to the inspected folder, including nested selections.
- Match duplicate group checkboxes, disclosure arrows and setup/history checkboxes to the native file lists.
- Improve Trash selection-bar spacing and use a restrained red accent for the final confirmation. Align Analyze with shared action buttons.
- Hide duplicate table headings before results exist and keep the start-check card usable in narrow panes.
- Place full-report duplicate filters beside Search, show active types with Reset, and mark type choices with shared colored icons and checkmarks.
- Ship Developer ID signed, Apple notarized and stapled universal builds for Apple Silicon and Intel.

## 0.15.3 — 2026-11-11

- View duplicates below the folder map alongside Contents and Largest files. Select a group or one copy to locate it without changing map scale; large groups use bounded folder highlights.
- Expand duplicate groups in a lazy list and keep the inspector stable while switching rows. Align table typography, dates, full copy paths and file-type icon colors.
- Use clear opaque map colors with neutral folder surfaces in light and dark mode.
- Unify action buttons and add sliding mode controls. Simplify duplicate setup to one checkbox; move appearance beside Language and contextual filters beside Search.
- Group New analysis, Repeat and Save on the left, separate adjacent actions, and extend file lists to the status bar. Remove agent-specific GUI controls; CLI/MCP remain available.
- Ship a Developer ID signed, notarized and stapled universal app and DMG for Apple Silicon and Intel, macOS 14+.

## 0.15.2 — 2026-11-09

- Developer ID signed, Apple notarized distribution for direct installation outside the App Store. Stapled tickets are included in the app and DMG.
- Preserve Apple Silicon and Intel support; no application features changed. Document the repeatable Keychain-based release workflow.

## 0.14.5 — 2026-11-08

- Keep the sidebar toggle beside the window controls by using a shared toolbar that does not track the sidebar divider. Preserve native split collapse, resizing and width persistence.
- Add 8 pt below the file-type legend so its text has breathing room above the map/list divider.

## 0.14.4 — 2026-11-08

- Match the native main toolbar background to the app palette in light and dark mode; use consistent borderless controls and secondary colors.
- Remove the repeated app title from the toolbar, give breadcrumbs clearer spacing/current-folder emphasis and full-path help, and omit the leading separator when showing the last three path components.
- Give icon actions meaningful accessible names and expose the New scan shortcut in hover help. Keep native window controls, resizing, toolbar overflow and pane toggles.

## 0.14.3 — 2026-11-08

- Center the author name and GitHub link in the native About panel.

## 0.14.2 — 2026-11-08

- Credit Maksim Popkov as the author in About, copyright, MIT license and both READMEs. Include a clickable GitHub repository link in About.

## 0.14.1 — 2026-11-08

- Use the shared sidebar section typography for Saved snapshots. Clicking anywhere on its heading expands or collapses the initially closed history.
- Separate selection from opening in the snapshots window: clicking a row only highlights it; the explicit Open button restores it to the workspace.

## 0.14.0 — 2026-11-08

- Match Saved snapshots to the app palette, with storage summary cards, lightweight separators, visible Open actions and snapshot-size headings instead of a system striped table.
- Put Add to analysis before Saved snapshots in navigation. Start the snapshot section collapsed and replace the ellipsis menu with an explicit All snapshots button.
- Restore per-snapshot size and delete controls in expanded sidebar history. Keep snapshot and duplicate-report weights distinct, with source-file safety explained in delete help and the existing confirmation flow.

## 0.13.1 — 2026-11-08

- Rename history to Saved snapshots throughout the window, sidebar, menus and links; use Recent snapshots on Home and Name in the storage table.

## 0.13.0 — 2026-11-08

- Separate saved-analysis storage into a resizable, nonmodal window: snapshot bytes, duplicate-report bytes and total history storage. Keep only name/date in recent analyses and remove storage weights from workspace status lines.
- Let the native divider allocate height between map and file list. Preserve map scope, tree disclosure, filters, Quick Look and stable Trash controls.
- Search all confirmed duplicate groups by name/path and load further batches of 500 in the app. Reuse the saved index, debounce typing and cache Unicode-folded paths; building and querying remain cancellable and off-main.
- Add Settings (⌘,), Find (⌘F / ⌥⌘F), New analysis (⌘N) and Open snapshot (⌘O). Persist appearance and optional date/share columns; support native column resizing and Shift-click checkbox ranges.
- Improve small captions and active-navigation contrast, with stronger secondary text/dividers in Increase Contrast. Open optional file-access guidance in its own window without stacking sheets.
- Explain nested-folder counts and incomplete branches in the inspector. Record local cloud-only metadata in new snapshots while keeping older snapshots readable. Scope the macOS no-materialization I/O policy to synchronous scanning and restore it on return or failure.
- Preserve explicit selection of every copy and mandatory Trash review. No CLI/MCP cleanup or automatic permission changes.

## 0.12.1 — 2026-11-08

- Show checked-item count and total size together in both Trash selection bars, within the existing fixed-height action row. Keep the amount visible when narrow layouts use icon actions.
- Sum ordinary files and complete folders from snapshot metadata off the main thread, using the selected size metric and counting folder/child overlaps once. Duplicate selections include every checked copy, including all copies of a group.
- Present optional Full Disk Access guidance as a calm shield card with an explanation, System Settings and Not now actions; never infer permission by probing protected files.

## 0.12.0 — 2026-11-08

- Expand folders inline with native disclosure arrows in Contents. Browse multiple levels without changing the map or current folder; retain flat search and Largest files.
- Load child pages from the existing snapshot off the main thread, 1,000 at a time with Show more. Preserve sorting, independent Trash checks and Quick Look for revealed children.
- Compact list controls and selection actions into two short rows, freeing room for file rows without moving the table when items are checked.
- Improve checked-row leading padding and keep tree entries on one line; leave full paths in the inspector and flat results.
- Add optional File access guidance at scan setup and skipped-path details. Explain ordinary macOS prompts and voluntary Full Disk Access, with a System Settings shortcut; never require or change permission automatically.
- Clarify the GitHub introduction and repository discovery topics around a WinDirStat alternative for Mac, disk space analysis and duplicate finding.

## 0.11.2 — 2026-11-08

- Fix the SwiftUI/AppKit sizing contract that could resist divider drags, leave stale content widths or snap the divider back after release.
- Remove the inspector's fixed 460-point maximum. Drag its divider toward the center as far as the available window space allows, while preserving a usable minimum width for the workspace.

## 0.11.1 — 2026-11-08

- Clear map/list highlights and temporary More groups by clicking empty workspace background, empty map gaps or the explicit Clear highlight action below the map.
- Preserve folder, search, filters, list mode and independent Trash checkboxes when clearing a highlight; remove its temporary context row without navigating.

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
