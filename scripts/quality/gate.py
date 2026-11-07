#!/usr/bin/env python3
"""Audit Sources and maintenance code; definitions and limits: docs/QUALITY.md."""

import argparse

from . import coverage_audit, graphs, python_audit, source_audit, swift_audit
from .common import AUDIT, ROOT, policy, read_json, run, write_json
from .coverage_audit import identity


def python_coverage():
    data = read_json(AUDIT / "python-coverage.json")
    return {
        name: {**dict.fromkeys(item["executed_lines"], 1), **dict.fromkeys(item["missing_lines"], 0)}
        for name, item in data["files"].items()
    }


def thresholds(config, prefix):
    return dict(
        coverage_min=config[prefix + "_line_coverage_min"],
        crap_average_below=config[prefix + "_crap_average_below"],
        crap_max=config[prefix + "_crap_max"],
    )


def audit_coverage(current, previous, revision, config):
    core = [row for row in current if row["file"].startswith("Sources/AtlasCore/")]
    scripts = [row for row in current if row["file"].startswith("scripts/") and "/tests/" not in row["file"]]
    core_result, errors = coverage_audit.measure(
        core, previous, swift_audit.core_coverage(), revision, thresholds(config, "changed_core")
    )
    swift_lines = read_json(AUDIT / "swift-script-lines.json")
    lines = python_coverage() | {
        path: {int(n): count for n, count in rows.items()} for path, rows in swift_lines.items()
    }
    files = [str(path.relative_to(ROOT)) for path in (ROOT / "scripts").rglob("*.py") if "tests" not in path.parts]
    files += ["scripts/icon.swift", "scripts/quality/metrics.swift"]
    script_result, failures = coverage_audit.measure(
        scripts, previous, lines, revision, thresholds(config, "changed_scripts"), files=files
    )
    return dict(core=core_result, scripts=script_result), [*errors, *failures]


def audit(revision):
    config = policy()
    swift_paths = swift_audit.swift_paths()
    python_paths = sorted((ROOT / "scripts").rglob("*.py"))
    current = swift_audit.metrics(swift_paths) + python_audit.current_metrics(python_paths)
    previous = {
        identity(row): row for row in swift_audit.revision_metrics(revision) + python_audit.revision_metrics(revision)
    }
    legacy = {identity(row): row for row in read_json(ROOT / "quality/legacy.json")["functions"]}
    errors, debt = source_audit.complexity_failures(current, legacy, config)
    errors += source_audit.file_failures(
        [*(ROOT / path for path in swift_paths), *python_paths], config["file_lines_max"]
    )
    errors += source_audit.clone_failures(current, previous)
    graph = dict(swift=graphs.swift_targets(), python=graphs.python_modules(python_paths))
    measured, failures = audit_coverage(current, previous, revision, config)
    return dict(
        base=revision,
        coverage=measured,
        known_complexity_debt=debt,
        dependency_graph=graph,
        functions=current,
        errors=[*errors, *failures],
    )


def print_report(report):
    for scope, value in report["coverage"].items():
        percent = "N/A (no executable changed lines)" if value["percent"] is None else f"{value['percent']:.1f}%"
        print(f"Changed {scope} line coverage: {percent}; CRAP avg/max: {value['crap_average']} / {value['crap_max']}")
    print("Circular dependencies: 0; frozen application complexity debt:", len(report["known_complexity_debt"]))
    for error in report["errors"]:
        print("FAIL:", error)
    if report["errors"]:
        raise SystemExit(1)
    print("PASS: quality gate. Full audit: .build/quality/report.json")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    args = parser.parse_args()
    run("git", "rev-parse", "--verify", args.base + "^{commit}")
    report = audit(args.base)
    write_json(AUDIT / "report.json", report)
    print_report(report)


if __name__ == "__main__":
    main()
