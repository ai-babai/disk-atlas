"""Validate the selected Xcode; policy.json is the only toolchain source."""

import subprocess

from .common import ROOT, policy, run


def validate_versions(config, xcode, swift, swift_file):
    expected = "Xcode " + config["xcode"] + "\nBuild version " + config["xcode_build"]
    if xcode.strip() != expected:
        raise ValueError("Use " + expected.replace("\n", ", ") + ". See CONTRIBUTING.md.")
    if "Apple Swift version " + config["swift"] + " " not in swift:
        raise ValueError("Swift " + config["swift"] + " is required by quality/policy.json.")
    if swift_file.strip() != config["swift"]:
        raise ValueError(".swift-version and quality/policy.json disagree.")


def verify():
    validate_versions(
        policy(),
        run("xcodebuild", "-version"),
        run("xcrun", "swift", "--version", stderr=subprocess.STDOUT),
        (ROOT / ".swift-version").read_text(),
    )


if __name__ == "__main__":
    verify()
