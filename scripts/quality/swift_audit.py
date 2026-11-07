"""SwiftSyntax and LLVM adapters; the gate itself stays language-independent."""

import json
import os
import tempfile
from pathlib import Path

from .common import AUDIT, ROOT, run
from .swift_tools import binary


def metrics(paths):
    if not paths:
        return []
    return json.loads(run("scripts/quality/metrics.sh", *map(str, paths)))


def swift_paths():
    return sorted(
        str(path.relative_to(ROOT)) for base in ["Sources", "scripts"] for path in (ROOT / base).rglob("*.swift")
    )


def revision_metrics(revision):
    paths = run("git", "ls-tree", "-r", "--name-only", revision, "--", "Sources", "scripts").splitlines()
    with tempfile.TemporaryDirectory(prefix="atlas-quality-base-") as directory:
        files = []
        for path in paths:
            if not path.endswith(".swift"):
                continue
            target = Path(directory) / path
            target.parent.mkdir(parents=True, exist_ok=True)
            source = run("git", "show", revision + ":" + path)
            formatted = run(
                "xcrun", "swift-format", "format", "--configuration", str(ROOT / ".swift-format"), "-", input=source
            )
            target.write_text(formatted)
            files.append(target)
        result = metrics(files)
        for item in result:
            item["file"] = str(Path(item["file"]).relative_to(directory))
        return result


def lcov_lines(text):
    result, current = {}, None
    for line in text.splitlines():
        if line.startswith("SF:"):
            current = os.path.relpath(line[3:], ROOT)
            result.setdefault(current, {})
        elif line.startswith("DA:") and current is not None:
            number, count = line[3:].split(",")[:2]
            result[current][int(number)] = max(int(count), result[current].get(int(number), 0))
        elif line == "end_of_record":
            current = None
    return result


def core_coverage():
    binary_dir = Path(run("swift", "build", "--show-bin-path").strip())
    executable = binary_dir / "DiskAtlasPackageTests.xctest/Contents/MacOS/DiskAtlasPackageTests"
    profile = binary_dir / "codecov/default.profdata"
    text = run("xcrun", "llvm-cov", "export", "-format=lcov", "-instr-profile=" + str(profile), str(executable))
    (AUDIT / "coverage.lcov").write_text(text)
    return lcov_lines(text)


def script_coverage():
    profiles = list((AUDIT / "script-profiles").glob("*.profraw"))
    if not profiles:
        raise ValueError("No Swift-script test profiles.")
    profile = AUDIT / "scripts.profdata"
    run("xcrun", "llvm-profdata", "merge", "-sparse", *map(str, profiles), "-o", str(profile))
    text = run(
        "xcrun",
        "llvm-cov",
        "export",
        "-format=lcov",
        "-instr-profile=" + str(profile),
        str(binary("metrics", True)),
        "-object",
        str(binary("icon", True)),
    )
    (AUDIT / "scripts.lcov").write_text(text)
    return lcov_lines(text)
