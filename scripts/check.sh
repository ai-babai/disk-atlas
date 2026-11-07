#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
atlas_base=''
atlas_clean=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --base) [ "$#" -ge 2 ] || exit 2; atlas_base=$2; shift 2 ;;
        --require-clean) atlas_clean=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
if "$atlas_clean"; then
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo 'Commit the reviewed changes before push. The hook must check the exact tree being sent.' >&2
        exit 1
    fi
fi
if [ -z "$atlas_base" ]; then atlas_base=$(git merge-base HEAD origin/main); fi
scripts/quality/toolchain.sh
mkdir -p .build/quality
printf '\n[1/6] Swift format / lint\n'
xcrun swift-format lint --strict --recursive Sources Tests scripts/quality/metrics.swift Package.swift
printf '\n[2/6] Compiler diagnostics\n'
swift build -Xswiftc -warnings-as-errors
printf '\n[3/6] Behavior / generated-property tests + LLVM coverage\n'
swift test --enable-code-coverage
printf '\n[4/6] Gate self-checks\n'
python3 -m unittest discover -s scripts/quality -p 'test_*.py'
printf '\n[5/6] Complexity, dependencies, changed-Core coverage and CRAP\n'
python3 scripts/quality/gate.py --base "$atlas_base"
printf '\n[6/6] Selected mutation checks (isolated temporary copy)\n'
python3 scripts/quality/mutations.py
printf '\nQuality gate passed. Report: .build/quality/report.json\n'
