#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/quality/toolchain.sh
atlas_hooks=$(git config --local --get core.hooksPath || true)
if [ -n "$atlas_hooks" ] && [ "$atlas_hooks" != '.githooks' ]; then
    echo "Existing local core.hooksPath: $atlas_hooks. Integrate .githooks/pre-push with it first; nothing overwritten." >&2
    exit 1
fi
git config --local core.hooksPath .githooks
printf 'Installed repository pre-push hook. Run scripts/check.sh; format fixes: scripts/format.sh\n'
