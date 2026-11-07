#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/quality/toolchain.sh
exec xcrun swift-format format --in-place --recursive Sources Tests scripts/quality/metrics.swift Package.swift
