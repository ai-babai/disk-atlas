"""Safe tool/bootstrap/build contracts on disposable paths, never owner app data."""

import contextlib
import hashlib
import io
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import build
from scripts.quality import bootstrap, driver, swift_tools, toolchain
from scripts.quality.common import ROOT


class BootstrapTests(unittest.TestCase):
    def test_cached_environment_and_requirement_invalidation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            requirements = root / "quality/requirements.txt"
            requirements.parent.mkdir()
            requirements.write_text("pinned==1")
            target = root / ".build/quality-tools"
            (target / "bin").mkdir(parents=True)
            (target / "bin/python3").touch()
            stamp = target / "requirements.sha256"
            stamp.write_text(bootstrap.fingerprint(requirements))
            with (
                patch.object(bootstrap.venv, "EnvBuilder") as builder,
                patch.object(bootstrap.subprocess, "run") as run,
            ):
                self.assertEqual(bootstrap.ensure_environment(root), target)
                builder.assert_not_called()
                requirements.write_text("pinned==2")
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(bootstrap.ensure_environment(root), target)
                self.assertIn("--require-hashes", run.call_args.args[0])
                self.assertIn("--only-binary=:all:", run.call_args.args[0])
                self.assertEqual(stamp.read_text(), bootstrap.fingerprint(requirements))

    def test_failed_install_never_creates_success_stamp(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            requirements = root / "quality/requirements.txt"
            requirements.parent.mkdir()
            requirements.write_text("pinned==1")
            target = root / ".build/quality-tools"
            target.mkdir(parents=True)
            with (
                patch.object(bootstrap.venv, "EnvBuilder"),
                patch.object(bootstrap.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "pip")),
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaises(subprocess.CalledProcessError),
            ):
                bootstrap.ensure_environment(root)
            self.assertFalse((target / "requirements.sha256").exists())
        with patch.object(bootstrap.sys, "version_info", (3, 8)), self.assertRaises(RuntimeError):
            bootstrap.ensure_environment()

    def test_bootstrap_forwards_arguments_without_interpretation(self):
        with (
            patch.object(bootstrap, "ensure_environment", return_value=Path("/private/tools")),
            patch.object(bootstrap.os, "execve") as execute,
            patch.object(sys, "argv", ["bootstrap", "check", "--base", "spaces; $(echo nope)"]),
        ):
            bootstrap.main()
        command, arguments, environment = execute.call_args.args
        self.assertEqual(command, "/private/tools/bin/python3")
        self.assertEqual(arguments[-3:], ["check", "--base", "spaces; $(echo nope)"])
        self.assertTrue(environment["PATH"].startswith("/private/tools/bin" + os.pathsep))


class AdapterTests(unittest.TestCase):
    def test_every_shell_entry_forwards_argv_cwd_and_exit_status(self):
        entries = {
            "scripts/check.sh": ["scripts.quality.bootstrap", "check"],
            "scripts/format.sh": ["scripts.quality.bootstrap", "format"],
            "scripts/setup-dev.sh": ["scripts.quality.bootstrap", "setup"],
            "scripts/build.sh": ["scripts.build", "build"],
            "scripts/release.sh": ["scripts.build", "release"],
            "scripts/quality/metrics.sh": ["scripts.quality.swift_tools", "metrics"],
            "scripts/quality/toolchain.sh": ["scripts.quality.toolchain"],
            ".githooks/pre-push": ["scripts.quality.hooks"],
        }
        with tempfile.TemporaryDirectory(prefix="atlas scripts Юникод ") as directory:
            root = Path(directory)
            fake = root / "bin/python3"
            fake.parent.mkdir()
            fake.write_text(
                "#!" + sys.executable + "\nimport os,sys,json\n"
                "print(json.dumps([os.getcwd(),sys.argv[1:]]))\nsys.exit(37)\n"
            )
            fake.chmod(0o755)
            environment = dict(os.environ, PATH=str(fake.parent) + os.pathsep + os.environ["PATH"])
            for name, expected in entries.items():
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, target)
                result = subprocess.run(
                    [str(target), "space ;$()", "--flag"], cwd="/", env=environment, text=True, capture_output=True
                )
                self.assertEqual(result.returncode, 37, result.stderr)
                self.assertEqual(
                    json.loads(result.stdout), [str(root.resolve()), ["-m", *expected, "space ;$()", "--flag"]]
                )


class ToolchainTests(unittest.TestCase):
    def test_pinned_toolchain_and_mismatches(self):
        config = dict(xcode="16.4", xcode_build="16F6", swift="6.1.2")
        xcode, swift, version = "Xcode 16.4\nBuild version 16F6", "Apple Swift version 6.1.2 (swiftlang)", "6.1.2\n"
        toolchain.validate_versions(config, xcode, swift, version)
        for values in [("wrong", swift, version), (xcode, "wrong", version), (xcode, swift, "wrong")]:
            with self.assertRaises(ValueError):
                toolchain.validate_versions(config, *values)
        toolchain.verify()

    def test_swift_binary_cache_invalidates_content_and_failed_compile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.swift"
            source.write_text("first")
            with (
                patch.object(swift_tools, "AUDIT", root),
                patch.object(swift_tools, "compiler_arguments", return_value=(source, ["compiler", str(source)])),
                patch.object(swift_tools, "run", return_value="version"),
                patch.object(swift_tools, "execute") as execute,
            ):
                target = swift_tools.binary("icon")
                target.touch()
                swift_tools.binary("icon")
                self.assertEqual(execute.call_count, 1)
                source.write_text("changed")
                swift_tools.binary("icon")
                self.assertEqual(execute.call_count, 2)
                successful_stamp = target.with_suffix(".sha256").read_text()
                source.write_text("broken")
                execute.side_effect = subprocess.CalledProcessError(1, "compiler")
                with self.assertRaises(subprocess.CalledProcessError):
                    swift_tools.binary("icon")
                self.assertEqual(target.with_suffix(".sha256").read_text(), successful_stamp)
        with (
            patch.object(swift_tools, "run", return_value="/missing/toolchain/usr/bin/swiftc"),
            self.assertRaisesRegex(RuntimeError, "SwiftSyntax"),
        ):
            swift_tools.compiler_arguments("metrics", False)


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="atlas-build-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Source App.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/MacOS/disk-atlas").write_text("binary")
        self.home = self.root / "fake home"
        self.target = self.home / "Applications/Disk Atlas.app"

    def write_bundle(self, identifier):
        (self.target / "Contents").mkdir(parents=True)
        (self.target / "Contents/Info.plist").write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier)))

    def test_unrelated_missing_metadata_and_symlink_targets_are_preserved(self):
        build.check_install_target(self.target)
        self.write_bundle("foreign.app")
        with self.assertRaisesRegex(ValueError, "unrelated"):
            build.check_install_target(self.target)
        self.assertEqual(
            plistlib.loads((self.target / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"], "foreign.app"
        )
        shutil.rmtree(self.target)
        self.target.symlink_to(self.root / "missing.app")
        with self.assertRaisesRegex(ValueError, "symlink"):
            build.check_install_target(self.target)
        self.target.unlink()
        self.target.mkdir()
        with self.assertRaises(FileNotFoundError):
            build.check_install_target(self.target)

    def test_install_preserves_existing_command_and_rejects_running_app(self):
        self.write_bundle("local.diskatlas.app")
        link = self.home / ".local/bin/disk-atlas"
        with (
            patch.object(build.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)),
            patch.object(build, "execute") as execute,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            build.install(self.app, self.home)
            self.assertTrue(link.is_symlink())
            execute.assert_called_once_with(["ditto", self.app, self.target])
            link.unlink()
            link.write_text("foreign command")
            build.install(self.app, self.home)
            self.assertEqual(link.read_text(), "foreign command")
        for status, error in [(0, ValueError), (2, RuntimeError)]:
            with (
                patch.object(build.subprocess, "run", return_value=subprocess.CompletedProcess([], status)),
                patch.object(build, "execute") as execute,
                self.assertRaises(error),
            ):
                build.install(self.app, self.home)
            execute.assert_not_called()

    def test_assembly_and_archives_contain_license_and_installer(self):
        binaries = self.root / "binaries"
        binaries.mkdir()
        for name in ["disk-atlas", "DiskAtlas"]:
            (binaries / name).write_text(name)
        with patch.object(build, "execute") as execute, patch.object(build, "invoke") as icon:
            build.assemble(self.app, binaries)
            self.assertEqual((self.app / "Contents/MacOS/DiskAtlas").read_text(), "DiskAtlas")
            self.assertTrue((self.app / "Contents/Resources/LICENSE.txt").is_file())
            self.assertEqual(
                (self.app / "Contents/Resources/Credits.rtf").read_bytes(),
                (build.ROOT / "Resources/Credits.rtf").read_bytes(),
            )
            icon.assert_called_once_with("icon", [str(self.app / "Contents/Resources")])
            self.assertIn("--verify", execute.call_args.args[0])
            stage = self.root / "stage"
            stage.mkdir()
            build.stage_image(self.app, stage)
            self.assertEqual(os.readlink(stage / "Applications"), "/Applications")
            self.assertTrue((stage / "INSTALL.txt").is_file())
            build.cli_archive(self.app, self.root / "cli.zip")
            self.assertEqual(execute.call_args.args[0][-1], self.root / "cli.zip")
        payload = self.root / "payload"
        payload.write_bytes(b"test" * 300_000)
        self.assertEqual(build.checksum(payload), hashlib.sha256(payload.read_bytes()).hexdigest())

    def test_packaging_checksums_match_all_three_assets(self):
        def create_asset(arguments):
            Path(arguments[-1]).write_bytes(b"archive")

        def cli_asset(_app, destination):
            destination.write_bytes(b"cli")

        def image_asset(arguments):
            if arguments[0] == "hdiutil":
                Path(arguments[-1]).write_bytes(b"dmg")
            else:
                create_asset(arguments)

        with (
            patch.object(build, "execute", side_effect=image_asset),
            patch.object(build, "cli_archive", side_effect=cli_asset),
        ):
            build.package(self.app, self.root, "test")
        lines = (self.root / "SHA256SUMS.txt").read_text().splitlines()
        self.assertEqual(len(lines), 3)
        for line in lines:
            digest, name = line.split("  ")
            self.assertEqual(digest, build.checksum(self.root / name))

    def test_build_release_orchestration_and_install_opt_in(self):
        with (
            patch.object(build, "execute"),
            patch.object(build, "assemble") as assemble,
            patch.object(build, "install") as install,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            build.build()
            install.assert_not_called()
            build.build(True)
            install.assert_called_once()
            self.assertEqual(assemble.call_count, 2)
        with patch.object(build, "execute") as execute:
            build.universal_binaries(self.root)
            self.assertEqual(execute.call_count, 4)
            self.assertEqual(execute.call_args.args[0][-1], self.root / "disk-atlas")
        with (
            patch.object(build, "ROOT", self.root),
            patch.object(build, "universal_binaries"),
            patch.object(build, "assemble"),
            patch.object(build, "package") as package,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            info = self.root / "Resources/Info.plist"
            info.parent.mkdir()
            info.write_bytes(plistlib.dumps(dict(CFBundleShortVersionString="test")))
            build.release()
            self.assertEqual(package.call_args.args[-1], "test")


class DriverTests(unittest.TestCase):
    def test_check_stops_on_failure_and_clean_tree_is_required(self):
        with patch.object(driver, "run", return_value="dirty"), self.assertRaises(ValueError):
            driver.clean_tree()
        calls = []

        def fail():
            calls.append("lint")
            raise RuntimeError("bad style")

        with (
            patch.object(driver, "run", return_value="base"),
            patch.object(driver, "clean_tree") as clean,
            patch.object(driver, "lint", side_effect=lambda _: fail()),
            patch.object(driver, "execute") as execute,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            with self.assertRaisesRegex(RuntimeError, "bad style"):
                driver.check(None, True)
            clean.assert_called_once()
            execute.assert_not_called()
        self.assertEqual(calls, ["lint"])

    def test_driver_commands_propagate_errors(self):
        for command in ["setup", "format", "check"]:
            with (
                patch.object(sys, "argv", ["driver", command]),
                patch.object(driver.toolchain, "verify"),
                patch.object(driver.hooks, "setup") as setup,
                patch.object(driver, "lint") as lint,
                patch.object(driver, "check") as check,
            ):
                driver.main()
                self.assertEqual(
                    (setup.call_count, lint.call_count, check.call_count),
                    tuple(int(command == item) for item in ["setup", "format", "check"]),
                )
        with (
            patch.object(sys, "argv", ["driver", "check"]),
            patch.object(driver.toolchain, "verify", side_effect=ValueError("bad toolchain")),
        ):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                driver.main()
            self.assertEqual(error.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
