---
type: Performance Notes
description: Measured map, panel and duplicate-check performance, reproducible workloads, dependency provenance and limits.
created: "2026-11-07"
---
# Runtime performance

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

## Duplicate checking in 0.8.0

Measured on the same Mac, release builds of 0.7.0 and the working 0.8.0 code,
three alternating trials per version, synthetic files only. Values are medians;
GB/MiB use their stated units. These are warm-cache tests, not a cold-drive or
external-HDD benchmark. `F_NOCACHE` is a hint, not proof that caches were cold.

| Workload | 0.7.0 elapsed / CPU | 0.8.0 elapsed / CPU | Logical content read |
| --- | ---: | ---: | ---: |
| Two identical 512 MiB files | 0.869 / 0.866 s | 0.520 / 0.495 s | 2,147,745,792 → 1,074,003,968 B |
| Three identical 512 MiB files | 1.532 / 1.521 s | 1.114 / 1.109 s | 3,758,489,600 B in both |

The pair avoids one whole-file hashing pass: size and edge samples already
establish the candidate pair, so byte comparison is sufficient. Larger buckets
still fingerprint every survivor to avoid quadratic comparison work. XXH3-128
replaces SHA-256 for candidate fingerprints. Exact byte comparison and the
existing descriptor/path identity checks remain mandatory; collisions split into
separate byte-equal groups. Small files retain the one-full-fingerprint path.

An isolated 1 MiB streaming buffer, repeated for 1 GiB of CPU work, measured
SHA-256/CryptoKit at 3.32 GB/s and XXH3-128 at 19.87 GB/s. That sixfold hash-only
throughput increase is not a sixfold application speed claim. A separate cached
streaming experiment with two workers improved wall time, but does not establish
cold-device behavior or lower energy. Production keeps one utility-priority
worker and foreground pause, rather than assuming that concurrent I/O helps every
device. CPU time fell about 43% for the pair and 27% for the triple. Power and
battery consumption were not measured; no watt-hour improvement is claimed.

Result-index preparation aggregates immediate parent counts before traversing
ancestors, and defers extension classification until a type filter requires it.
Index construction and per-copy JSON encoding have cancellation checkpoints.
Stop stays available during report saving. Atomic report replacement preserves
the previous committed report when cancellation occurs before commit. Quit
cancels jobs and terminates immediately; unsaved current results may be lost,
while committed history remains available.

### Hash dependency and audit boundary

CXXHash statically compiles the unmodified [xxHash 0.8.3 header](https://github.com/Cyan4973/xxHash/blob/v0.8.3/xxhash.h).
Header SHA-256: `17973c0dc49d9854ca26caa191f0e12f7a424b68858d9a78de3860d959d85e4b`.
The [BSD-2-Clause license](../Resources/ThirdParty/xxHash-LICENSE.txt) is bundled
with app and standalone CLI. The three-line C translation unit enables the
upstream implementation; handwritten ownership remains in the small Swift
ContentFingerprint adapter. No runtime package installation or network is needed.
See [upstream algorithm documentation](https://xxhash.com/doc/v0.8.3/group___x_x_h3__family.html).

The existing numerical complexity/coverage gate analyzes first-party Swift and
maintenance Python, not vendored upstream C. C compilation uses `-Wall -Wextra
-Werror` for both release architectures. Behavior tests verify reference vectors,
streaming boundaries, actual duplicate groups, byte-read counts, collision
partitioning and cancellation. Passing these checks is not a claim of full
upstream C coverage or a formal proof of the hash algorithm.

## 0.13.0 follow-up

On macOS 15.8.1 / Apple M4 Pro / Swift 6.1.2 (`-O`), the same warm-APFS fixture
of 20,000 empty files and 100 folders gave a five-run median of 122 ms for the
0.12.1 scan and 121 ms for 0.13.0. Presentation-index construction changed from
19 ms to 21 ms, including the new branch aggregates. These results do not establish
a scanner speedup. A sorted query over 40,000 confirmed groups took about 13 ms.

A rare-name query in the new GUI search initially took 179–180 ms. Preparing
Unicode-folded paths once (32 ms for that index) reduced the same two queries to
42–44 ms. The search waits for a 120 ms typing pause, then runs off-main with
cancellation and generation checks. More groups can be loaded in batches of 500.

An eight-second `sample` during real divider drags in a release QA window with
3,434 files found the main thread waiting for messages in 688/732 samples, and
one treemap packing sample. This is a short interaction sample, not an FPS or
battery-life guarantee. No live cloud data was downloaded for verification.
The scoped no-materialization policy follows [Apple TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files).
See the [detailed method and limits](PERFORMANCE.ru.md).
