#!/usr/bin/env python3
"""Project gate: syntax metrics + LLVM coverage. Definitions: docs/QUALITY.md."""
import argparse
import collections
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs)


def metrics(paths):
    if not paths:
        return []
    return json.loads(run('scripts/quality/metrics.sh', *map(str, paths)))


def identity(item):
    return item['file'], item['identity']


def revision_metrics(revision):
    paths = run('git', 'ls-tree', '-r', '--name-only', revision, '--', 'Sources').splitlines()
    with tempfile.TemporaryDirectory(prefix='atlas-quality-base-') as directory:
        files = []
        for path in paths:
            if not path.endswith('.swift'):
                continue
            target = Path(directory) / path
            target.parent.mkdir(parents=True, exist_ok=True)
            source = run('git', 'show', revision + ':' + path)
            formatted = run('xcrun', 'swift-format', 'format', '--configuration', str(ROOT / '.swift-format'), '-', input=source)
            target.write_text(formatted)
            files.append(target)
        result = metrics(files)
        for item in result:
            item['file'] = str(Path(item['file']).relative_to(directory))
        return result


def lcov_lines(text):
    """Use LLVM's own executable-line list, not guesses from Swift text."""
    result, current = {}, None
    for line in text.splitlines():
        if line.startswith('SF:'):
            current = os.path.relpath(line[3:], ROOT)
            result.setdefault(current, {})
        elif line.startswith('DA:') and current is not None:
            number, count = line[3:].split(',')[:2]
            result[current][int(number)] = max(int(count), result[current].get(int(number), 0))
        elif line == 'end_of_record':
            current = None
    return result


def coverage():
    binary_dir = Path(run('swift', 'build', '--show-bin-path').strip())
    executable = binary_dir / 'DiskAtlasPackageTests.xctest/Contents/MacOS/DiskAtlasPackageTests'
    profile = binary_dir / 'codecov/default.profdata'
    text = run('xcrun', 'llvm-cov', 'export', '-format=lcov', '-instr-profile=' + str(profile), str(executable))
    (ROOT / '.build/quality/coverage.lcov').write_text(text)
    return lcov_lines(text)


def added_lines(revision, path):
    exists = subprocess.run(['git', 'cat-file', '-e', revision + ':' + path], cwd=ROOT, capture_output=True).returncode == 0
    if not exists:
        return set(range(1, len((ROOT / path).read_text().splitlines()) + 1))
    diff = run('git', 'diff', '--no-ext-diff', '--unified=0', revision, '--', path)
    lines = set()
    for start, size in re.findall(r'^@@ .*?\+(\d+)(?:,(\d+))? @@', diff, re.MULTILINE):
        lines.update(range(int(start), int(start) + int(size or '1')))
    return lines


def complexity_failures(current, legacy, policy):
    errors, debt = [], []
    for item in current:
        if item['cyclomatic'] <= policy['cyclomatic_max'] and item['cognitive'] <= policy['cognitive_max']:
            continue
        known = legacy.get(identity(item))
        label = f"{item['file']}:{item['start']} {item['identity']} CC={item['cyclomatic']} cognitive={item['cognitive']}"
        if known and known['bodyHash'] == item['bodyHash']:
            debt.append(label)
        else:
            errors.append(label)
    return errors, debt


def coverage_result(current, previous, lines, revision, policy):
    functions, changed_lines = [], {}
    for item in current:
        if not item['file'].startswith('Sources/AtlasCore/'):
            continue
        old = previous.get(identity(item))
        if old and old['bodyHash'] == item['bodyHash']:
            continue
        functions.append(item)
        changed_lines.setdefault(item['file'], set()).update(range(item['start'], item['end'] + 1))
    rows, errors = [], []
    for item in functions:
        executable = {n: count for n, count in lines.get(item['file'], {}).items() if item['start'] <= n <= item['end']}
        if not executable:
            errors.append(f"No LLVM coverage for changed function: {item['file']}:{item['start']}")
            continue
        covered = sum(count > 0 for count in executable.values()) / len(executable)
        cc = item['cyclomatic']
        rows.append(dict(function=item['identity'], file=item['file'], coverage=covered * 100,
                         crap=cc ** 2 * (1 - covered) ** 3 + cc))
    eligible = covered = 0
    for path, semantic in changed_lines.items():
        diff = added_lines(revision, path)
        for number, count in lines.get(path, {}).items():
            if number in semantic and number in diff:
                eligible += 1
                covered += count > 0
    percent = covered / eligible * 100 if eligible else None
    if percent is not None and percent < policy['changed_core_line_coverage_min']:
        errors.append(f"Changed Core line coverage {percent:.1f}% < {policy['changed_core_line_coverage_min']}%")
    if rows:
        average = sum(row['crap'] for row in rows) / len(rows)
        maximum = max(row['crap'] for row in rows)
        if average >= policy['changed_core_crap_average_below']:
            errors.append(f"Changed Core CRAP average {average:.2f} is not < {policy['changed_core_crap_average_below']}")
        if maximum > policy['changed_core_crap_max']:
            errors.append(f"Changed Core CRAP maximum {maximum:.2f} > {policy['changed_core_crap_max']}")
    else:
        average = maximum = None
    return dict(eligible_lines=eligible, covered_lines=covered, percent=percent, crap_average=average,
                crap_max=maximum, functions=rows), errors


def dependencies():
    package = json.loads(run('swift', 'package', 'dump-package'))
    graph = {target['name']: [next(iter(dep.values()))[0] for dep in target['dependencies']] for target in package['targets']}
    def visit(node, active, done):
        if node in active:
            raise ValueError('Circular target dependency: ' + ' -> '.join(active + [node]))
        if node in done:
            return
        for child in graph.get(node, []):
            visit(child, active + [node], done)
        done.add(node)
    done = set()
    for target in graph:
        visit(target, [], done)
    forbidden = re.compile(r'^\s*(?:@testable\s+)?import\s+(AppKit|SwiftUI|DiskAtlas|AtlasCLI)\b', re.MULTILINE)
    for path in (ROOT / 'Sources/AtlasCore').glob('*.swift'):
        if forbidden.search(path.read_text()):
            raise ValueError('Core must not depend on GUI/CLI: ' + str(path.relative_to(ROOT)))
    return graph


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', required=True)
    args = parser.parse_args()
    run('git', 'rev-parse', '--verify', args.base + '^{commit}')
    policy = json.loads((ROOT / 'quality/policy.json').read_text())
    paths = sorted(str(path.relative_to(ROOT)) for path in (ROOT / 'Sources').rglob('*.swift'))
    current = metrics(paths)
    previous = {identity(row): row for row in revision_metrics(args.base)}
    legacy = {identity(row): row for row in json.loads((ROOT / 'quality/legacy.json').read_text())['functions']}
    errors, debt = complexity_failures(current, legacy, policy)
    for path in paths:
        if len((ROOT / path).read_text().splitlines()) > policy['file_lines_max']:
            errors.append(f"{path}: exceeds {policy['file_lines_max']} lines; split responsibilities")
    clones = collections.defaultdict(list)
    for item in current:
        if item['end'] - item['start'] >= 8:
            clones[item['bodyHash']].append(item)
    for group in clones.values():
        if len(group) > 1 and any(previous.get(identity(row), {}).get('bodyHash') != row['bodyHash'] for row in group):
            errors.append('New exact function-body duplication: ' + ', '.join(row['file'] + ':' + str(row['start']) for row in group))
    graph = dependencies()
    measured, failures = coverage_result(current, previous, coverage(), args.base, policy)
    errors.extend(failures)
    report = dict(base=args.base, scope='all Sources complexity; semantic changed AtlasCore executable lines/CRAP',
                  coverage=measured, known_complexity_debt=debt, target_graph=graph, functions=current, errors=errors)
    (ROOT / '.build/quality/report.json').write_text(json.dumps(report, indent=2) + '\n')
    value = measured['percent']
    print('Changed Core line coverage:', 'N/A (no executable changed lines)' if value is None else f"{value:.1f}%")
    print('Changed Core CRAP avg/max:', measured['crap_average'], measured['crap_max'])
    print('Circular target dependencies: 0; frozen pre-existing complexity debt:', len(debt))
    for error in errors:
        print('FAIL:', error)
    if errors:
        raise SystemExit(1)
    print('PASS: quality gate. Full audit and existing debt: .build/quality/report.json')


if __name__ == '__main__':
    main()
