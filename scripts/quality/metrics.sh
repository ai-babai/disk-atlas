#!/bin/sh
set -eu
CDPATH=''
cd "$(dirname "$0")/../.."
exec python3 -m scripts.quality.swift_tools metrics "$@"
