---
type: Quality Contract
description: Reproducible contributor checks, metric definitions, scope, frozen legacy debt and review principles.
created: "2026-11-07"
---
# One quality gate

```sh
scripts/setup-dev.sh   # once per clone: verify tools and install the pre-push hook
scripts/check.sh       # the same command used by the hook and GitHub Actions
```

Requires **Xcode 16.4 (16F6), Apple Swift 6.1.2**, and Python 3.9+. No pip,
Homebrew, paid service, account or API key is needed. Set `DEVELOPER_DIR` for that
Xcode if several versions are installed. The compiler, `swift-format`, SwiftSyntax
parser and LLVM coverage tools come from the selected, checked toolchain.
Versions and thresholds are committed in [policy.json](../quality/policy.json).

Fix formatting with `scripts/format.sh`. For another comparison base, use
`scripts/check.sh --base <commit>`. The default is the merge base with `origin/main`.
The hook uses the actual pushed range and refuses dirty/untracked work, because
checking a different working tree would not validate the commit being sent.
Git intentionally does not activate hooks on clone; run setup once. An existing
custom hooks path is preserved, with an integration instruction instead of overwrite.

## What blocks a change

| Check | Contract and scope |
| --- | --- |
| Style and compiler | Strict `swift-format` lint; compiler warnings are errors; all application targets build. |
| Cyclomatic complexity | ≤10 per new/changed function or computed-property accessor block in `Sources`. |
| Cognitive complexity | ≤15 with the documented structural SwiftSyntax rules below. |
| Coverage of changes | ≥80% of changed executable **AtlasCore** lines in semantically changed functions, measured by LLVM LCOV. |
| CRAP | Average <5, maximum ≤30 for new/changed **AtlasCore** functions, using LLVM line coverage as a proxy. |
| Dependencies | Zero SwiftPM target cycles; AtlasCore cannot import GUI/CLI modules. |
| Exact duplication / file size | Reject new identical function bodies of at least 9 lines; source files ≤1,000 lines. |
| Properties | Deterministically generated ordering, permutation, tie stability, top-K and filtering invariants, plus storage safety behavior tests. |
| Mutations | All four committed sorting mutations must compile and be detected by tests. A build/environment error is a failed check, not a killed mutant. |

The gate exits nonzero on failure. Fix the code/tests and rerun it before pushing.
Do not use `--no-verify`, raise thresholds or regenerate exceptions to make a change
appear green. CI runs the same command on PRs and main and retains audit artifacts.
A maintainer can make the `quality` status required in branch rules; local hooks
alone cannot enforce settings on someone else's clone.

## Measurements, without false guarantees

The [SwiftSyntax analyzer](../scripts/quality/metrics.swift) parses Swift syntax;
comments and strings cannot masquerade as control flow. A function starts at CC 1;
`if`, `guard`, loops, catches, ternaries, switch cases and each `&&`/`||` add one.
Cognitive complexity counts control-flow breaks and nesting, boolean-operator
sequences, `else`, and nesting inside closures; guards do not increase nesting.
A switch adds one cognitive break, its cases only affect CC. An `else if` adds one
without another nesting level. Nested named functions are measured separately.
These are **project-defined structural metrics**, not a SonarQube certification;
recursion/call-graph analysis and every Swift semantic construct are not modeled.
The analyzer has executable self-checks.

Coverage uses LLVM's executable-line records, not regex guesses about Swift.
Formatting-only function bodies are identified by syntax-token hashes and do not
create artificial coverage debt. New/untracked Core files are included. Missing
coverage fails. No changed executable lines is reported as **N/A**, never 100%.
The base revision, eligible/covered counts and per-function values are in
`.build/quality/report.json`; LCOV is alongside it.

`CRAP = CC² × (1 − coverage)³ + CC`. Here coverage is **line coverage**, not basis-path
coverage. SwiftUI/AppKit and CLI lines are **not included in this coverage/CRAP
threshold**; they still receive formatting, build and complexity checks and need
native interaction review. The gate does not claim 80% coverage of the entire app.
The selected four mutations protect the sorting contract; their 4/4 result is not
a whole-project mutation score. Additional mutation operators need meaningful
behavior tests and an explicit contract update.

## Existing debt is visible

The first audit of revision `e5f7721` found 29 functions/accessor blocks over the
complexity limits. The modified duplicate-results body was split into cohesive
sections and the version-touched MCP handler was split by responsibility,
reducing the frozen exceptions to **27**.
[legacy.json](../quality/legacy.json) records only those pre-existing bodies and
exact hashes. An edited body loses its exception even if its score did not grow;
new or changed code must satisfy the thresholds. Existing exceptions and all
current scores are printed in the full report. **A passing change gate does not
mean the entire historical codebase meets the bar.** Remove an exception when
that responsibility is refactored; do not silently expand the baseline.

## Principles that still need review

- **DRY:** keep a behavior/rule in one place. Exact clone detection cannot prove
  that two different implementations represent the same business rule.
- **KISS:** use the simplest clear solution for the observed workflow. A small
  metric alone does not establish a simple design.
- **YAGNI:** tie each option or abstraction to an executable current requirement;
  avoid framework/configuration growth for hypothetical uses.
- **SOLID / SRP:** keep each module cohesive, with clear contracts and a reason to
  change. Prefer narrow boundaries, deep useful modules and explicit side effects
  to many trivial wrappers. Domain names and observable behavior matter.
- **Safe feedback and refactoring:** start with an observed failure or requirement,
  test the behavior, preserve source data, make small reviewable changes and keep
  expensive work off the main thread. Review failure/cancellation paths as well
  as the happy path.

PRs should explain the behavior, responsibility boundary, relevant properties and
actual check results. These questions apply the engineering principles behind
the quality bar; neither a book list nor a green linter replaces judgment.

Sources: [swift-format configuration](https://github.com/swiftlang/swift-format/blob/main/Documentation/Configuration.md),
[SwiftSyntax](https://github.com/swiftlang/swift-syntax),
[Apple coverage guidance](https://developer.apple.com/documentation/xcode/determining-how-much-code-your-tests-cover),
[CRAP's original definition](https://www.artima.com/weblogs/viewpost.jsp?thread=210575),
[Sonar cognitive complexity background](https://www.sonarsource.com/resources/cognitive-complexity/).
