---
type: Performance Notes
description: Scope, reproducible workload and limits of the native panel and map profiling performed for 0.4.0.
created: "2026-11-07"
---
# Map and panel profiling

Measured on macOS 15.8.1, Apple Silicon, optimized Swift 6.1.2 builds. The synthetic
snapshot has 998,400 files and 409 folders; no user file contents were profiled.
Index construction took about 0.38–0.44 seconds and already runs off the main thread.

The bounded map was exercised with 30 size changes, 30 selection changes and 30
unrelated progress updates. Temporary counters measured map body/layout/Canvas
preparation, with a native hosting-view draw to flush lazy SwiftUI updates.

| Selection workload, 30 changes | Before | After |
| --- | ---: | ---: |
| Nested Canvas preparations | 720 | 30 |
| Summed Canvas preparation time | 69.3 ms | 5.0 ms |
| Layout calls | 750 | 60 |
| Summed layout time | 4.92 ms | 0.63 ms |
| Map body evaluations for 30 unrelated progress updates | 30 | 0 |

These are **preparation measurements**, not screen FPS or whole-app speedups.
Bitmap capture dominates the offscreen draw harness and is excluded from speed
claims. Real size changes still redraw the affected geometry; layout itself was
small enough that changing the packing algorithm was not justified. Selection
is now passed only into its own tile branch, and unrelated store changes stop at
an explicit map-state boundary.

Native panel transitions were sampled in a live window. Four collapse/expand
operations produced 12–15 distinct intermediate content widths, rather than one
jump. The no-animation branch used by Reduce Motion produced one width per
transition. A dragged 260-point navigation pane returned at 260 points. Transitions
use AppKit's split item animator with a 220 ms ease-in/ease-out duration. No artificial
loading delay is added. SwiftUI environment values cross the hosting boundaries.

The 0.4.0 interaction check covered immediate single-click selection, double-click
target stability after revealing a parent, nested-file hits and inert aggregates.
In 0.5.2, single-click selection no longer reveals/navigates to a parent directory;
activation requires a second click on the same entry.
Native clicks also verified selection and folder opening. `sample` call stacks
were inspected during panel transitions; raw profiling files are local scratch
material and are not committed or published.

Run `scripts/check.sh` for the maintained behavior/quality suite. Manual performance
comparisons should use release builds, the same synthetic tree and window size,
separate warm-up from measurement and distinguish preparation from presentation.
The temporary profiling harness is not a new permanent benchmark framework.
