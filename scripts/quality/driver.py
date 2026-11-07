"""One entry point for local checks, formatting and hook setup."""

import argparse
import os
import shutil
import subprocess
import sys

from . import gate, hooks, mutations, shell_audit, swift_audit, swift_tools, toolchain
from .common import AUDIT, ROOT, execute, run, write_json


def clean_tree():
    if run("git", "status", "--porcelain").strip():
        raise ValueError("Commit reviewed changes before push; the gate must check the exact tree being sent.")


def lint(write=False):
    shell_audit.lint(write)
    execute(["ruff", "check", *(["--fix"] if write else []), "scripts"])
    execute(["ruff", "format", *([] if write else ["--check"]), "scripts"])
    execute(
        [
            "xcrun",
            "swift-format",
            "format" if write else "lint",
            *(["--in-place"] if write else ["--strict"]),
            "--recursive",
            "Sources",
            "Tests",
            "scripts",
            "Package.swift",
        ]
    )


def test_scripts():
    profiles = AUDIT / "script-profiles"
    shutil.rmtree(profiles, ignore_errors=True)
    profiles.mkdir(parents=True)
    for name in ["metrics", "icon"]:
        swift_tools.binary(name, True)
    environment = dict(
        os.environ,
        ATLAS_SWIFT_SCRIPT_COVERAGE="1",
        LLVM_PROFILE_FILE=str(profiles / "%m-%p.profraw"),
        COVERAGE_RCFILE=str(ROOT / ".coveragerc"),
        COVERAGE_FILE=str(AUDIT / "python-coverage/.coverage"),
    )
    (AUDIT / "python-coverage").mkdir(parents=True, exist_ok=True)
    for arguments in [
        ["erase"],
        ["run", "-m", "unittest", "discover", "-s", "scripts/tests"],
        ["combine"],
        ["json", "-o", str(AUDIT / "python-coverage.json")],
    ]:
        execute([sys.executable, "-m", "coverage", *arguments], env=environment)
    write_json(AUDIT / "swift-script-lines.json", swift_audit.script_coverage())


def check(base, require_clean):
    if require_clean:
        clean_tree()
    revision = base or run("git", "merge-base", "HEAD", "origin/main").strip()
    run("git", "rev-parse", "--verify", revision + "^{commit}")
    steps = [
        ("Swift/Python/shell style and shell adapter checks", lambda: lint(False)),
        ("Compiler diagnostics", lambda: execute(["swift", "build", "-Xswiftc", "-warnings-as-errors"])),
        ("Core behavior/properties + LLVM coverage", lambda: execute(["swift", "test", "--enable-code-coverage"])),
        ("CLI, maintenance behavior/properties + Python/Swift-script coverage", test_scripts),
        ("Complexity, dependencies, changed-line coverage and CRAP", lambda: gate.print_report(save_audit(revision))),
        ("Selected Swift and script mutations", mutations.main),
    ]
    for number, (title, operation) in enumerate(steps, 1):
        print(f"\n[{number}/{len(steps)}] {title}", flush=True)
        operation()
    print("\nQuality gate passed. Report: .build/quality/report.json")


def save_audit(revision):
    report = gate.audit(revision)
    write_json(AUDIT / "report.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "format", "setup"])
    parser.add_argument("--base")
    parser.add_argument("--require-clean", action="store_true")
    args = parser.parse_args()
    try:
        toolchain.verify()
        if args.command == "setup":
            hooks.setup()
        elif args.command == "format":
            lint(True)
        else:
            check(args.base, args.require_clean)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
