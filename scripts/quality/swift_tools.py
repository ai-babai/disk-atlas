"""Compile/cache the two Swift maintenance tools with the selected toolchain."""

import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path

from .common import AUDIT, ROOT, execute, run


def compiler_arguments(name, profiled):
    compiler = run("xcrun", "--find", "swiftc").strip()
    source = ROOT / ("scripts/icon.swift" if name == "icon" else "scripts/quality/metrics.swift")
    sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path").strip()
    arguments = [compiler, "-sdk", sdk, "-parse-as-library", str(source)]
    if name == "metrics":
        host = Path(compiler).parent.parent / "lib/swift/host"
        if not host.is_dir():
            raise RuntimeError("Selected Xcode is missing SwiftSyntax host libraries.")
        arguments += [
            "-I",
            str(host),
            "-L",
            str(host),
            "-lSwiftSyntax",
            "-lSwiftParser",
            "-Xlinker",
            "-rpath",
            "-Xlinker",
            str(host),
        ]
    if profiled:
        arguments += ["-profile-generate", "-profile-coverage-mapping"]
    return source, arguments


def binary(name, profiled=False):
    source, arguments = compiler_arguments(name, profiled)
    target = AUDIT / "swift-tools" / (name + ("-profiled" if profiled else ""))
    stamp = target.with_suffix(".sha256")
    version = run("xcrun", "swiftc", "--version", stderr=subprocess.STDOUT)
    digest = hashlib.sha256(source.read_bytes() + (repr(arguments) + version).encode()).hexdigest()
    if target.exists() and stamp.exists() and stamp.read_text() == digest:
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    execute([*arguments, "-o", target])
    stamp.write_text(digest)
    return target


def invoke(name, arguments):
    target = binary(name, profiled=os.environ.get("ATLAS_SWIFT_SCRIPT_COVERAGE") == "1")
    execute([target, *arguments])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("tool", choices=["metrics", "icon"])
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        invoke(args.tool, args.arguments)
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
