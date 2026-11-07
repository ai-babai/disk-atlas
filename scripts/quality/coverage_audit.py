"""Changed executable-line coverage and per-function CRAP for either language."""

import re
import subprocess

from .common import ROOT, run


def identity(item):
    return item["file"], item["identity"]


def added_lines(revision, path):
    exists = (
        subprocess.run(["git", "cat-file", "-e", revision + ":" + path], cwd=ROOT, capture_output=True).returncode == 0
    )
    if not exists:
        return set(range(1, len((ROOT / path).read_text().splitlines()) + 1))
    diff = run("git", "diff", "--no-ext-diff", "--unified=0", revision, "--", path)
    lines = set()
    for start, size in re.findall(r"^@@ .*?\+(\d+)(?:,(\d+))? @@", diff, re.MULTILINE):
        lines.update(range(int(start), int(start) + int(size or "1")))
    return lines


def changed_functions(current, previous):
    return [item for item in current if previous.get(identity(item), {}).get("bodyHash") != item["bodyHash"]]


def function_coverage(item, lines):
    executable = {n: count for n, count in lines.get(item["file"], {}).items() if item["start"] <= n <= item["end"]}
    if not executable:
        raise ValueError(f"No coverage for changed function: {item['file']}:{item['start']}")
    covered = sum(count > 0 for count in executable.values()) / len(executable)
    cc = item["cyclomatic"]
    return dict(
        function=item["identity"], file=item["file"], coverage=covered * 100, crap=cc**2 * (1 - covered) ** 3 + cc
    )


def diff_coverage(functions, lines, revision, files=None):
    semantic = {}
    for item in functions:
        semantic.setdefault(item["file"], set()).update(range(item["start"], item["end"] + 1))
    if files is not None:
        semantic = {path: set(lines.get(path, {})) for path in files}
    eligible = covered = 0
    for path, numbers in semantic.items():
        diff = added_lines(revision, path)
        counts = [count for number, count in lines.get(path, {}).items() if number in numbers and number in diff]
        eligible += len(counts)
        covered += sum(count > 0 for count in counts)
    return eligible, covered


def coverage_failures(percent, rows, thresholds):
    errors = []
    if percent is not None and percent < thresholds["coverage_min"]:
        errors.append(f"Changed line coverage {percent:.1f}% < {thresholds['coverage_min']}%")
    if rows:
        average = sum(row["crap"] for row in rows) / len(rows)
        maximum = max(row["crap"] for row in rows)
        if average >= thresholds["crap_average_below"]:
            errors.append(f"CRAP average {average:.2f} is not < {thresholds['crap_average_below']}")
        if maximum > thresholds["crap_max"]:
            errors.append(f"CRAP maximum {maximum:.2f} > {thresholds['crap_max']}")
    return errors


def measure(current, previous, lines, revision, thresholds, files=None):
    functions = changed_functions(current, previous)
    rows, errors = [], []
    if files is not None:
        errors.extend("No coverage record for script: " + path for path in files if path not in lines)
    for item in functions:
        try:
            rows.append(function_coverage(item, lines))
        except ValueError as error:
            errors.append(str(error))
    eligible, covered = diff_coverage(functions, lines, revision, files)
    percent = covered / eligible * 100 if eligible else None
    errors.extend(coverage_failures(percent, rows, thresholds))
    return dict(
        eligible_lines=eligible,
        covered_lines=covered,
        percent=percent,
        crap_average=sum(row["crap"] for row in rows) / len(rows) if rows else None,
        crap_max=max((row["crap"] for row in rows), default=None),
        functions=rows,
    ), errors
