#!/usr/bin/env python3
"""Selected observable mutation contracts; never change the working tree."""

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .common import AUDIT, ROOT, read_json

LOGS = AUDIT / "mutations"


def test(directory):
    result = subprocess.run(
        ["swift", "test", "--package-path", str(directory), "--filter", "DuplicateOrderingTests"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    return result.returncode, result.stdout


def detected(code, output):
    return (
        code == 1
        and "Build complete!" in output
        and re.search(r": error: .*XCTAssert\w* failed", output) is not None
        and "unexpected signal" not in output
    )


def python_test(directory):
    result = subprocess.run(
        [sys.executable, "-m", "unittest", "scripts.tests.test_audit"],
        cwd=directory,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    return result.returncode, result.stdout


def python_detected(code, output):
    return code == 1 and "FAIL: " in output and "FAILED (failures=" in output and "ERROR:" not in output


def check_baseline(directory, runner, label):
    code, output = runner(directory)
    (LOGS / (label + "-baseline.log")).write_text(output)
    if code:
        raise RuntimeError(label + " mutation baseline failed; see .build/quality/mutations/")


def check_mutant(directory, mutant, runner, detector):
    path = directory / mutant["file"]
    original = path.read_text()
    if original.count(mutant["from"]) != 1:
        raise ValueError("Mutation anchor must match exactly once: " + mutant["id"])
    try:
        path.write_text(original.replace(mutant["from"], mutant["to"], 1))
        code, output = runner(directory)
        (LOGS / (mutant["id"] + ".log")).write_text(output)
        if code == 0:
            raise RuntimeError("SURVIVED: " + mutant["id"] + "; strengthen observable behavior tests")
        if not detector(code, output):
            raise RuntimeError("INVALID/environment failure, not a killed mutant: " + mutant["id"])
        print("KILLED:", mutant["id"], flush=True)
    finally:
        path.write_text(original)


def suite(manifest, runner, detector, names, label):
    mutants = read_json(ROOT / manifest)
    with tempfile.TemporaryDirectory(prefix="atlas-mutations-") as temporary:
        directory = Path(temporary)
        for name in names:
            source = ROOT / name
            if source.is_dir():
                shutil.copytree(source, directory / name, ignore=shutil.ignore_patterns("__pycache__"))
            else:
                shutil.copyfile(source, directory / name)
        check_baseline(directory, runner, label)
        for mutant in mutants:
            check_mutant(directory, mutant, runner, detector)
    print(f"PASS: {len(mutants)}/{len(mutants)} selected {label} mutants killed (not a whole-project score)")


def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    suite("quality/mutations.json", test, detected, ["Sources", "Tests", "Package.swift", "Package.resolved"], "Swift")
    suite("quality/script-mutations.json", python_test, python_detected, ["scripts", "quality"], "Python")


if __name__ == "__main__":
    main()
