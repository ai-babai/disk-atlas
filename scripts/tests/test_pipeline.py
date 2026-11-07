"""Exercise the gate as a complete consumer, including its missing-data behavior."""

import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import build
from scripts.quality import driver, gate, mutations, shell_audit, swift_audit
from scripts.quality.common import ROOT, read_json


class PipelineTests(unittest.TestCase):
    def test_self_audit_includes_all_languages_and_rejects_missing_coverage(self):
        def audit_input(path):
            return {} if path.name == "swift-script-lines.json" else read_json(path)

        with (
            patch.object(gate, "python_coverage", return_value={}),
            patch.object(swift_audit, "core_coverage", return_value={}),
            patch.object(gate, "read_json", side_effect=audit_input),
        ):
            report = gate.audit("HEAD")
        paths = {row["file"] for row in report["functions"]}
        self.assertIn("scripts/build.py", paths)
        self.assertIn("scripts/icon.swift", paths)
        self.assertIn("scripts/quality/metrics.swift", paths)
        self.assertIn("scripts/tests/test_audit.py", paths)
        self.assertTrue(any("No coverage record for script:" in error for error in report["errors"]))
        self.assertIn("scripts.quality.gate", report["dependency_graph"]["python"])
        self.assertEqual(report["coverage"]["scripts"]["functions"], [])

    def test_python_coverage_preserves_missing_lines(self):
        data = dict(files={"scripts/example.py": dict(executed_lines=[1, 3], missing_lines=[2])})
        with patch.object(gate, "read_json", return_value=data):
            self.assertEqual(gate.python_coverage(), {"scripts/example.py": {1: 1, 2: 0, 3: 1}})

    def test_gate_cli_saves_audit_and_fails_with_the_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = dict(errors=["bad code"])
            with (
                patch.object(gate, "AUDIT", root),
                patch.object(gate, "audit", return_value=report),
                patch.object(sys, "argv", ["gate", "--base", "HEAD"]),
                patch.object(gate, "print_report", side_effect=SystemExit(1)),
                self.assertRaises(SystemExit),
            ):
                gate.main()
            self.assertEqual(read_json(root / "report.json"), report)

    def test_all_check_stages_run_in_order(self):
        calls = []
        with (
            patch.object(driver, "run", return_value="base"),
            patch.object(driver, "lint", side_effect=lambda _: calls.append("lint")),
            patch.object(driver, "execute", side_effect=lambda args: calls.append(args[1])),
            patch.object(driver, "test_scripts", side_effect=lambda: calls.append("scripts")),
            patch.object(driver, "save_audit", side_effect=lambda _: calls.append("audit")),
            patch.object(gate, "print_report"),
            patch.object(mutations, "main", side_effect=lambda: calls.append("mutations")),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            driver.check("base", False)
        self.assertEqual(calls, ["lint", "build", "test", "scripts", "audit", "mutations"])
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(driver, "AUDIT", Path(directory)),
            patch.object(gate, "audit", return_value=dict(errors=[])),
        ):
            self.assertEqual(driver.save_audit("base"), dict(errors=[]))

    def test_style_checks_include_scripts_in_both_modes(self):
        for write in [False, True]:
            with patch.object(driver, "execute") as execute, patch.object(shell_audit, "lint") as shell:
                driver.lint(write)
                shell.assert_called_once_with(write)
                commands = [call.args[0] for call in execute.call_args_list]
                self.assertIn("scripts", commands[-1])
                self.assertEqual("--fix" in commands[0], write)
            with patch.object(shell_audit, "execute") as execute:
                shell_audit.lint(write)
                self.assertEqual(execute.call_count, 2)

    def test_script_runner_propagates_profile_config_to_children(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with (
                patch.object(driver, "AUDIT", root),
                patch.object(driver, "execute") as execute,
                patch.object(driver.swift_tools, "binary"),
                patch.object(swift_audit, "script_coverage", return_value={}),
            ):
                driver.test_scripts()
            calls = execute.call_args_list
            self.assertEqual([call.args[0][3] for call in calls], ["erase", "run", "combine", "json"])
            environment = calls[1].kwargs["env"]
            self.assertEqual(environment["COVERAGE_RCFILE"], str(ROOT / ".coveragerc"))
            self.assertEqual(environment["ATLAS_SWIFT_SCRIPT_COVERAGE"], "1")
            self.assertTrue(Path(environment["COVERAGE_FILE"]).is_absolute())
            self.assertTrue((root / "swift-script-lines.json").is_file())

    def test_build_command_dispatch_and_errors(self):
        for arguments, command in [(["build"], "build"), (["release"], "release")]:
            with patch.object(sys, "argv", ["build", *arguments]), patch.object(build, command) as operation:
                build.main()
                operation.assert_called_once()
        with (
            patch.object(sys, "argv", ["build", "build"]),
            patch.object(build, "build", side_effect=ValueError("foreign app")),
        ):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                build.main()
            self.assertEqual(error.exception.code, 1)

    def test_selected_mutation_suite_never_edits_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "scripts"
            source.mkdir()
            (source / "sample.py").write_text("original")
            (root / "manifest.json").write_text("[]")
            with (
                patch.object(mutations, "ROOT", root),
                patch.object(mutations, "LOGS", root),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                mutations.suite(
                    "manifest.json",
                    lambda _: (0, "ok"),
                    mutations.python_detected,
                    ["scripts", "manifest.json"],
                    "Python",
                )
            self.assertEqual((source / "sample.py").read_text(), "original")
        with patch.object(mutations.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "ok")):
            self.assertEqual(mutations.test(Path("/tmp/example")), (0, "ok"))
            self.assertEqual(mutations.python_test(Path("/tmp/example")), (0, "ok"))
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(mutations, "suite") as suite,
            patch.object(mutations, "LOGS", Path(directory)),
        ):
            mutations.main()
            self.assertEqual(suite.call_count, 2)


if __name__ == "__main__":
    unittest.main()
