---
type: Design Guide
description: Shared Disk Atlas button and mode-control styling; consult before adding action controls.
created: "2026-11-11"
---
# Controls

The owner chose the existing Finder/Copy path inspector actions as the visual
reference. Keep the green interface palette and the native window/menu shell.
The feeling is calm, clear, consistent; content and the map remain primary.

`AtlasControls.swift` owns command surfaces:

- `AtlasButtonStyle`: system 11 pt, 10 pt horizontal inset, radius 6, height 28 pt,
  including Analyze and sheet confirmation actions.
- Rest uses `Palette.soft`, `Palette.ink` and a subtle `Palette.line` outline. Hover uses a gentle `Palette.mark`;
  pressed uses the full mark. These states do not change geometry or animate.
- Emphasized/default actions and selected modes use the same marked surface,
  accent text and a subtle accent outline. Keyboard focus has a stronger outline.
- Destructive-role actions use the same geometry with a muted red surface, red
  text and outline. Only the explicit final Trash confirmation receives this
  destructive treatment; opening its review stays neutral.
- Disabled controls retain their position and use muted text. The native Button
  still owns actions, disabled behavior, shortcuts and accessibility roles.
- `AtlasSegments` groups mutually exclusive real buttons inside one 32 pt surface,
  with 28 pt button targets. Inactive labels use `Palette.sub`; the selected label
  uses `Palette.selectedText` over `Palette.mark`.
  A single persistent pill moves between measured button bounds in 240 ms,
  including width changes. Only the pill animates; Reduce Motion skips the movement.
  Selected state is exposed to accessibility; Left/Right moves selection within the focused group.
  Draw focus on the selected pill only: group focus propagates to its children,
  so grouped button surfaces must never draw their own focus borders.
  Use it for list modes and physical/logical size, without changing the map scope.
- Inspector actions, filters, Trash selection actions, Home commands, snapshot Open,
  and dialog commands share this family. File/filter presets use the same selected
  surface. Auxiliary windows receive it through `atlasAppearance`.

Keep table-row hit targets, disclosure arrows, checkbox controls, column headings,
text links and native toolbar/menu items appropriate to their roles. They do not
become large filled command buttons. Destructive actions retain their native role,
full-path review and explicit confirmation; a style change cannot alter those rules.

Verify both themes, the minimum window, selected/disabled/focused states and
keyboard operation after changing these components. Use only synthetic data in
screenshots intended for the public repository. No diagnostic gallery is shipped.

Appearance lives in the trailing toolbar beside Language on Home and results; no second theme control in the sidebar or Home heading. File-type icons fit 16×16 pt with the same 9 pt icon/text gap as native table cells, including wide code symbols.

The mode control stays mounted above both table bodies; hidden layout placeholders preserve alignment while its selection pill and keyboard focus survive a mode change.

Filters appear once to the left of the list search: ordinary size/date criteria for Contents/Largest, duplicate-result criteria for Duplicates. No filter button sits above the map. Each context keeps its existing criteria and behavior.

Home keeps duplicate setup to one checkbox; checking it does not expand more controls
or retain hidden size/type restrictions. File access guidance sits at the right below
the folder drop area. In the results toolbar, New analysis, Repeat and Save sit on
the left after navigation. Thin noninteractive separators divide navigation,
New analysis, Repeat and Save into separate targets. Language and appearance stay on the right;
Save snapshot uses a diskette silhouette, with its accessible name and shortcut hint.
Agent context belongs to automation/documentation, not the inspector surface.

Duplicate group checkboxes and disclosure arrows use AppKit controls to match the
file outline, including mixed selection. Disclosure arrows keep their 24 pt column
and a 24×40 pt hit area, separate from Trash checks and map selection.
Find duplicates on the setup screen reuses the same checkbox with an 11 pt native
title; clicking either the box or its title changes the option.
Compact Trash selection bars reserve 36 pt in every state: 28 pt buttons have
4 pt above and below, inside an 8 pt rounded container. Checking items cannot
change the table's header position.

Duplicate table headings appear only with actual groups. The preparation/estimate,
in-progress-without-matches and empty-result states have no empty table header.
Those states fit the available panel width; the table's minimum width applies
only when there are result rows.

In the full duplicate report, Filters sits immediately before search, as in the
embedded list. Type choices use the shared colored file icons and a checkmark for
each selected type; multiple types can be combined. Active types/size/date filters
remain visible beside Reset after closing the popover. Filtering uses the entire
saved result index and keeps every copy in each matching group; it does not start
a new check or alter the saved report.

The workspace list extends to the status bar without bottom page padding. Reserve
the small list-status row only for an actual empty-result or presentation-limit
message; an invisible message must not consume table height.

Inspector file-type totals and expanded extensions describe the inspected folder,
including a single-click selection that leaves the map at its current level. With
no selection they describe the open folder. Hide folder composition for individual
files; their type already appears in the file details. Changing the inspected folder
resets expanded extension rows and cancels the previous folder's metadata request.
