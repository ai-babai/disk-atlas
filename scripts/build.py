"""Build, sign and package the existing app; preserve foreign install targets."""

import argparse
import hashlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .quality.common import ROOT, execute
from .quality.swift_tools import invoke


def assemble(app, binaries):
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    for name in ["DiskAtlas", "disk-atlas"]:
        shutil.copy2(binaries / name, macos / name)
    shutil.copy2(ROOT / "Resources/Info.plist", app / "Contents/Info.plist")
    shutil.copy2(ROOT / "LICENSE", resources / "LICENSE.txt")
    execute(["ditto", ROOT / "Resources/ThirdParty", resources / "ThirdParty"])
    invoke("icon", [str(resources)])
    execute(["codesign", "--force", "--deep", "--sign", "-", app])
    execute(["codesign", "--verify", "--deep", "--strict", app])


def check_install_target(target):
    if not target.exists() and not target.is_symlink():
        return
    if target.is_symlink():
        raise ValueError("Install target is a symlink; review it yourself: " + str(target))
    info = plistlib.loads((target / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.diskatlas.app":
        raise ValueError("Refusing to replace an unrelated app: " + str(target))


def install(app, home):
    target = home / "Applications/Disk Atlas.app"
    check_install_target(target)
    running = subprocess.run(["/usr/bin/pgrep", "-x", "DiskAtlas"], capture_output=True)
    if running.returncode == 0:
        raise ValueError("Close Disk Atlas before installing the new bundle.")
    if running.returncode != 1:
        raise RuntimeError("Could not check whether Disk Atlas is running.")
    target.parent.mkdir(parents=True, exist_ok=True)
    execute(["ditto", app, target])
    directory = home / ".local/bin"
    directory.mkdir(parents=True, exist_ok=True)
    link = directory / "disk-atlas"
    if not link.exists() and not link.is_symlink():
        link.symlink_to(target / "Contents/MacOS/disk-atlas")
    print("Installed:", target)


def build(install_requested=False):
    execute(["swift", "build", "-c", "release"])
    app = ROOT / "dist/Disk Atlas.app"
    assemble(app, ROOT / ".build/release")
    if install_requested:
        install(app, Path.home())
    print("Built:", app)


def universal_binaries(directory):
    for architecture in ["arm64", "x86_64"]:
        execute(["swift", "build", "-c", "release", "--arch", architecture])
    for name in ["DiskAtlas", "disk-atlas"]:
        inputs = [ROOT / ".build" / (arch + "-apple-macosx/release") / name for arch in ["arm64", "x86_64"]]
        execute(["lipo", "-create", *inputs, "-output", directory / name])


def stage_image(app, directory):
    execute(["ditto", app, directory / "Disk Atlas.app"])
    (directory / "Applications").symlink_to("/Applications")
    shutil.copy2(ROOT / "docs/INSTALL.txt", directory / "INSTALL.txt")
    shutil.copy2(ROOT / "LICENSE", directory / "LICENSE.txt")


def cli_archive(app, destination):
    with tempfile.TemporaryDirectory(prefix="disk-atlas-cli-release-") as temporary:
        stage = Path(temporary)
        shutil.copy2(app / "Contents/MacOS/disk-atlas", stage / "disk-atlas")
        shutil.copy2(ROOT / "LICENSE", stage / "LICENSE.txt")
        shutil.copytree(ROOT / "Resources/ThirdParty", stage / "ThirdParty")
        shutil.copy2(ROOT / "docs/CLI-INSTALL.txt", stage / "README.txt")
        execute(["ditto", "-c", "-k", stage, destination])


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package(app, directory, version):
    name = "Disk-Atlas-" + version + "-universal"
    assets = [
        directory / (name + ".dmg"),
        directory / (name + ".zip"),
        directory / ("disk-atlas-cli-" + version + "-universal.zip"),
    ]
    with tempfile.TemporaryDirectory(prefix="disk-atlas-release-") as temporary:
        stage = Path(temporary)
        stage_image(app, stage)
        execute(
            ["hdiutil", "create", "-volname", "Disk Atlas", "-srcfolder", stage, "-format", "UDZO", "-ov", assets[0]]
        )
    execute(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, assets[1]])
    cli_archive(app, assets[2])
    (directory / "SHA256SUMS.txt").write_text("".join(checksum(path) + "  " + path.name + "\n" for path in assets))


def release():
    directory = ROOT / "dist/release"
    directory.mkdir(parents=True, exist_ok=True)
    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    with tempfile.TemporaryDirectory(prefix="disk-atlas-binaries-") as temporary:
        binaries = Path(temporary)
        universal_binaries(binaries)
        app = directory / "Disk Atlas.app"
        assemble(app, binaries)
    package(app, directory, version)
    print("Universal release:", directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    local = commands.add_parser("build")
    local.add_argument("--install", action="store_true")
    commands.add_parser("release")
    args = parser.parse_args()
    try:
        if args.command == "release":
            release()
        else:
            build(args.install)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
