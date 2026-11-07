#!/usr/bin/env python3
"""The policy file is the single machine-readable toolchain source."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
policy = json.loads((root / 'quality/policy.json').read_text())
xcode = subprocess.check_output(['xcodebuild', '-version'], text=True).strip()
expected = 'Xcode ' + policy['xcode'] + '\nBuild version ' + policy['xcode_build']
if xcode != expected:
    raise SystemExit('Use ' + expected.replace('\n', ', ') + '. See CONTRIBUTING.md.')
swift = subprocess.check_output(['xcrun', 'swift', '--version'], text=True, stderr=subprocess.STDOUT)
if 'Apple Swift version ' + policy['swift'] + ' ' not in swift:
    raise SystemExit('Swift ' + policy['swift'] + ' is required by quality/policy.json.')
if (root / '.swift-version').read_text().strip() != policy['swift']:
    raise SystemExit('.swift-version and quality/policy.json disagree.')
