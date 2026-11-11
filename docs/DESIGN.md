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

- `AtlasButtonStyle`: system 11 pt, 10 pt horizontal inset, radius 6, height 28 pt.
  The existing large Analyze action uses the same geometry at 32 pt height.
- Rest uses `Palette.soft`, `Palette.ink` and a subtle `Palette.line` outline. Hover uses a gentle `Palette.mark`;
  pressed uses the full mark. These states do not change geometry or animate.
- Emphasized/default actions and selected modes use the same marked surface,
  accent text and a subtle accent outline. Keyboard focus has a stronger outline.
- Disabled controls retain their position and use muted text. The native Button
  still owns actions, disabled behavior, shortcuts and accessibility roles.
- `AtlasSegments` groups mutually exclusive real buttons inside one 28 pt surface.
  The selected pill moves between intrinsic-width labels, with Reduce Motion honored.
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
the folder drop area. In the results toolbar, New analysis precedes Repeat and Save;
Save snapshot uses a diskette silhouette, with its accessible name and shortcut hint.
Agent context belongs to automation/documentation, not the inspector surface.
