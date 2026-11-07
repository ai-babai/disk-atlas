## Behavior

What concrete workflow or failure changes? Include before/after behavior.

## Design and safety

- [ ] DRY / KISS: one owning rule, simplest clear solution.
- [ ] YAGNI / SRP: current requirement, cohesive responsibility and explicit boundaries.
- [ ] Source files remain safe; errors/cancellation and native UI waits are handled.

## Validation

- [ ] `scripts/check.sh --base <base-commit>` passes; include coverage/CRAP and mutation results.
- [ ] Existing debt or scope limitations are stated; thresholds/exceptions were not relaxed to pass.
- [ ] Native UI changes reviewed in EN/RU, both themes and minimum window size.
