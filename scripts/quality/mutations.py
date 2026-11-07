#!/usr/bin/env python3
"""A selected, explicit mutation contract; never changes the working tree."""
import json
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LOGS = ROOT / '.build/quality/mutations'


def test(directory):
    result = subprocess.run(['swift', 'test', '--package-path', str(directory), '--filter', 'DuplicateOrderingTests'],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    return result.returncode, result.stdout


def detected(code, output):
    return (code == 1 and 'Build complete!' in output
            and re.search(r': error: .*XCTAssert\w* failed', output) is not None
            and 'unexpected signal' not in output)


def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    mutants = json.loads((ROOT / 'quality/mutations.json').read_text())
    with tempfile.TemporaryDirectory(prefix='atlas-mutations-') as temporary:
        directory = Path(temporary)
        for name in ['Sources', 'Tests']:
            shutil.copytree(ROOT / name, directory / name)
        shutil.copyfile(ROOT / 'Package.swift', directory / 'Package.swift')
        code, output = test(directory)
        (LOGS / 'baseline.log').write_text(output)
        if code:
            raise SystemExit('Mutation baseline failed; see .build/quality/mutations/baseline.log')
        for mutant in mutants:
            path = directory / mutant['file']
            original = path.read_text()
            if original.count(mutant['from']) != 1:
                raise SystemExit('Mutation anchor must match exactly once: ' + mutant['id'])
            try:
                path.write_text(original.replace(mutant['from'], mutant['to'], 1))
                code, output = test(directory)
                (LOGS / (mutant['id'] + '.log')).write_text(output)
                if not code:
                    raise SystemExit('SURVIVED: ' + mutant['id'] + '; strengthen observable behavior tests')
                if not detected(code, output):
                    raise SystemExit('INVALID / environment failure, not a killed mutant: ' + mutant['id'])
                print('KILLED:', mutant['id'], flush=True)
            finally:
                path.write_text(original)
    print(f"PASS: {len(mutants)}/{len(mutants)} selected mutants killed (not a whole-project mutation score)")


if __name__ == '__main__':
    main()
