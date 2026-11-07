"""Quality contracts fail closed; generated inputs exercise threshold boundaries."""

import ast
import contextlib
import io
import itertools
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.quality import coverage_audit as coverage
from scripts.quality import gate, graphs, hooks, mutations, python_audit, shell_audit, source_audit, swift_audit
from scripts.quality.common import ROOT, policy, read_json, write_json


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.row = dict(file="scripts/example.py", identity="f", start=1, end=5, cyclomatic=3, bodyHash="new")
        self.thresholds = dict(coverage_min=80, crap_average_below=5, crap_max=30)

    def test_threshold_boundaries(self):
        for percent in range(101):
            with self.subTest(percent=percent):
                errors = coverage.coverage_failures(percent, [], self.thresholds)
                self.assertEqual(bool(errors), percent < 80)
        self.assertEqual(coverage.coverage_failures(None, [], self.thresholds), [])
        self.assertTrue(coverage.coverage_failures(100, [dict(crap=5)], self.thresholds))
        self.assertEqual(len(coverage.coverage_failures(100, [dict(crap=31)], self.thresholds)), 2)

    def test_actual_counts_and_no_double_counting_overlaps(self):
        lines = {self.row["file"]: {1: 1, 2: 0, 3: 4, 4: 0, 5: 1}}
        with patch.object(coverage, "added_lines", return_value={1, 2, 3}):
            result, errors = coverage.measure([self.row, self.row], {}, lines, "base", self.thresholds)
            self.assertEqual((result["eligible_lines"], result["covered_lines"]), (3, 2))
            self.assertAlmostEqual(result["functions"][0]["crap"], 3 + 9 * 0.4**3)
            self.assertTrue(errors)

    def test_changed_files_include_top_level_and_missing_function_fails(self):
        with patch.object(coverage, "added_lines", return_value={1, 6}):
            result, errors = coverage.measure(
                [self.row], {}, {self.row["file"]: {6: 1}}, "base", self.thresholds, files=[self.row["file"]]
            )
        self.assertEqual(result["percent"], 100)
        self.assertIn("No coverage", errors[0])
        unchanged = {coverage.identity(self.row): self.row}
        result, errors = coverage.measure([self.row], unchanged, {}, "base", self.thresholds)
        self.assertIsNone(result["percent"])
        self.assertEqual(errors, [])
        with patch.object(coverage, "added_lines", return_value=set()):
            _, errors = coverage.measure([], {}, {}, "base", self.thresholds, files=["new.py"])
        self.assertIn("No coverage record", errors[0])

    def test_diff_new_deleted_and_existing_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "new.py").write_text("one\ntwo\n")
            with (
                patch.object(coverage, "ROOT", root),
                patch.object(coverage.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)),
            ):
                self.assertEqual(coverage.added_lines("base", "new.py"), {1, 2})
        diff = "@@ -1 +1,2 @@\n@@ -8 +9,0 @@\n@@ -10 +11 @@\n"
        with (
            patch.object(coverage.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)),
            patch.object(coverage, "run", return_value=diff),
        ):
            self.assertEqual(coverage.added_lines("base", "file.py"), {1, 2, 11})


class StructureTests(unittest.TestCase):
    def test_each_complexity_limit_independently_blocks(self):
        limits = dict(cyclomatic_max=10, cognitive_max=15)
        for cc, cognitive in itertools.product(range(9, 13), range(14, 18)):
            row = dict(file="x", identity="f", start=1, cyclomatic=cc, cognitive=cognitive, bodyHash="a")
            errors, debt = source_audit.complexity_failures([row], {}, limits)
            self.assertEqual(bool(errors), cc > 10 or cognitive > 15)
            self.assertEqual(debt, [])

    def test_clone_contract_and_file_limit(self):
        first = dict(file="x", identity="f", start=1, end=9, bodyHash="same")
        second = dict(first, file="y")
        self.assertTrue(source_audit.clone_failures([first, second], {}))
        previous = {coverage.identity(row): row for row in [first, second]}
        self.assertEqual(source_audit.clone_failures([first, second], previous), [])
        self.assertEqual(source_audit.clone_failures([dict(first, end=8), second], {}), [])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "file"
            path.write_text("a\nb\n")
            self.assertEqual(source_audit.file_failures([path], 2), [])
            self.assertTrue(source_audit.file_failures([path], 1))

    def graph_from_bits(self, bits):
        graph = {str(i): [] for i in range(3)}
        for index, (first, second) in enumerate(itertools.product(range(3), repeat=2)):
            if bits & (1 << index):
                graph[str(first)].append(str(second))
        return graph

    def cyclic_by_closure(self, graph):
        reachable = {node: set(children) for node, children in graph.items()}
        for _ in range(3):
            reachable = {n: targets | set().union(*(reachable[t] for t in targets)) for n, targets in reachable.items()}
        return any(node in targets for node, targets in reachable.items())

    def test_all_small_dependency_graphs(self):
        # Every three-node directed graph, including self-edges; compare with transitive closure.
        for bits in range(512):
            graph = self.graph_from_bits(bits)
            if self.cyclic_by_closure(graph):
                with self.assertRaisesRegex(ValueError, "Circular dependency"):
                    graphs.validate(graph)
            else:
                self.assertEqual(graphs.validate(graph), graph)

    def test_python_imports_relative_cycles_and_layer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            first, second = root / "scripts/a.py", root / "scripts/b.py"
            first.write_text("from . import b\n")
            second.write_text("import os\n")
            with patch.object(graphs, "ROOT", root):
                self.assertEqual(graphs.python_modules([first, second])["scripts.a"], ["scripts.b"])
                second.write_text("import scripts.a\n")
                with self.assertRaises(ValueError):
                    graphs.python_modules([first, second])
                second.write_text("from scripts.tests import test_audit\n")
                with self.assertRaisesRegex(ValueError, "cannot import tests"):
                    graphs.python_modules([second])

    def test_python_metrics_ignore_comments_and_track_nested_scopes(self):
        source = '''"""if while for"""
import os
VALUE = 1
class Example:
    def method(self, flag):
        def nested():
            return 1
        if flag:
            return nested()
        return 0
async def task():
    return "while"
if __name__ == '__main__':
    print(VALUE)
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.py"
            path.write_text(source)
            rows = python_audit.metrics(path)
            self.assertEqual([row["identity"] for row in rows], ["Example.method", "Example.method.nested", "task"])
            self.assertEqual([row["cyclomatic"] for row in rows], [2, 1, 1])
            digest = rows[0]["bodyHash"]
            path.write_text(source.replace("return 0", "return 0  # comment"))
            self.assertEqual(python_audit.metrics(path)[0]["bodyHash"], digest)
            with patch.object(python_audit, "code_complexity") as absent:
                absent.return_value.functions = []
                with self.assertRaisesRegex(ValueError, "Missing function metrics"):
                    python_audit.metrics(path)
        with self.assertRaisesRegex(ValueError, "module-level"):
            python_audit.validate_toplevel(ast.parse("print('unmeasured')"))

    def test_shell_adapters_are_parsed_not_searched(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "adapter.sh"
            path.write_text('#!/bin/sh\n# if while for\nexec python3 -m scripts.build "$@"\n')
            shell_audit.validate_adapter(path)
            for body in ["if true; then echo x; fi", "false || true", "f() { echo x; }"]:
                path.write_text("#!/bin/sh\n" + body + "\n")
                with self.assertRaisesRegex(ValueError, "branching"):
                    shell_audit.validate_adapter(path)
            path.write_text("#!/bin/bash\nexit 0\n")
            with self.assertRaisesRegex(ValueError, "POSIX"):
                shell_audit.validate_adapter(path)


class HookTests(unittest.TestCase):
    def test_exact_checked_out_commit_required(self):
        with (
            patch.object(hooks, "run", side_effect=["head\n", "other\n"]),
            self.assertRaisesRegex(ValueError, "exact commit"),
        ):
            hooks.pushed_bases(["refs/heads/topic other refs/heads/topic old"])

    def test_multiple_refs_cover_all_ranges_and_deletions(self):
        lines = ["refs/heads/a head refs/heads/a old-a", "refs/heads/b head refs/heads/b " + hooks.ZERO]
        with (
            patch.object(hooks, "run", side_effect=["head", "head", "head", "ancestor"]) as run,
            patch.object(hooks, "execute") as execute,
        ):
            hooks.check(lines)
            self.assertEqual(run.call_args.args, ("git", "merge-base", "--octopus", "HEAD", "old-a", "origin/main"))
            execute.assert_called_once_with(["scripts/check.sh", "--base", "ancestor", "--require-clean"])
        with patch.object(hooks, "run", return_value="head"), patch.object(hooks, "execute") as execute:
            hooks.check([f"refs/heads/deleted {hooks.ZERO} refs/heads/deleted old"])
            execute.assert_not_called()
        with patch.object(hooks, "run", return_value="head"), self.assertRaises(ValueError):
            hooks.pushed_bases(["malformed"])

    def test_checked_tags_and_environment_failure(self):
        for status in [0, 1]:
            with patch.object(hooks.subprocess, "run", return_value=subprocess.CompletedProcess([], status)):
                self.assertEqual(hooks.checked_tag("refs/tags/v1", "commit"), status == 0)
        with (
            patch.object(hooks.subprocess, "run", return_value=subprocess.CompletedProcess([], 128)),
            self.assertRaisesRegex(RuntimeError, "Fetch"),
        ):
            hooks.checked_tag("refs/tags/v1", "commit")
        with (
            patch.object(hooks, "run", side_effect=["head", "head"]),
            patch.object(hooks, "checked_tag", return_value=True),
        ):
            self.assertEqual(hooks.pushed_bases(["refs/tags/v1 head refs/tags/v1 old"]), [])

    def test_setup_preserves_effective_custom_hook(self):
        for existing in ["", ".githooks", "/global/custom"]:
            result = subprocess.CompletedProcess([], 0, existing, "")
            with patch.object(hooks.subprocess, "run", return_value=result), patch.object(hooks, "execute") as execute:
                if existing == "/global/custom":
                    with self.assertRaisesRegex(ValueError, "nothing overwritten"):
                        hooks.setup()
                    execute.assert_not_called()
                else:
                    with contextlib.redirect_stdout(io.StringIO()):
                        hooks.setup()
                    execute.assert_called_once()
        with (
            patch.object(hooks.subprocess, "run", return_value=subprocess.CompletedProcess([], 128, "", "broken")),
            self.assertRaises(RuntimeError),
        ):
            hooks.setup()


class ReportsTests(unittest.TestCase):
    def test_json_and_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested/report.json"
            write_json(path, dict(ok=True))
            self.assertEqual(read_json(path), dict(ok=True))
        self.assertEqual(policy()["changed_scripts_line_coverage_min"], 80)

    def test_report_failure_and_na(self):
        report = dict(
            coverage=dict(core=dict(percent=None, crap_average=None, crap_max=None)),
            known_complexity_debt=[],
            errors=[],
        )
        with contextlib.redirect_stdout(io.StringIO()) as output:
            gate.print_report(report)
        self.assertIn("N/A", output.getvalue())
        report["errors"] = ["missing coverage"]
        report["coverage"]["core"]["percent"] = 90
        with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            gate.print_report(report)

    def test_lcov_merges_counts_and_resets_at_record(self):
        text = f"DA:1,99\nSF:{ROOT}/scripts/icon.swift\nDA:2,0\nDA:2,3\nend_of_record\nDA:3,8\n"
        self.assertEqual(swift_audit.lcov_lines(text), {"scripts/icon.swift": {2: 3}})
        self.assertEqual(swift_audit.metrics([]), [])
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(swift_audit, "AUDIT", Path(directory)),
            self.assertRaisesRegex(ValueError, "No Swift-script"),
        ):
            swift_audit.script_coverage()

    def test_mutation_results_do_not_confuse_errors_with_failures(self):
        self.assertTrue(mutations.python_detected(1, "FAIL: test_rule\nFAILED (failures=1)"))
        self.assertFalse(mutations.python_detected(1, "ERROR: test_rule\nFAILED (errors=1)"))
        self.assertFalse(mutations.python_detected(0, "FAIL: test_rule\nFAILED (failures=1)"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "sample.py"
            path.write_text("original")
            mutant = dict(id="contract", file="sample.py", **{"from": "original", "to": "changed"})
            with patch.object(mutations, "LOGS", root):
                mutations.check_baseline(root, lambda _: (0, "ok"), "test")
                with self.assertRaisesRegex(RuntimeError, "baseline"):
                    mutations.check_baseline(root, lambda _: (1, "bad"), "test")
                for status, output, message in [(0, "ok", "SURVIVED"), (1, "error", "INVALID")]:
                    with self.assertRaisesRegex(RuntimeError, message):
                        mutations.check_mutant(
                            root, mutant, lambda _, s=status, o=output: (s, o), mutations.python_detected
                        )
                    self.assertEqual(path.read_text(), "original")
                with contextlib.redirect_stdout(io.StringIO()):
                    mutations.check_mutant(
                        root, mutant, lambda _: (1, "FAIL: test\nFAILED (failures=1)"), mutations.python_detected
                    )
                self.assertEqual(path.read_text(), "original")
                mutant["from"] = "absent"
                with self.assertRaisesRegex(ValueError, "anchor"):
                    mutations.check_mutant(root, mutant, lambda _: (0, ""), mutations.python_detected)


if __name__ == "__main__":
    unittest.main()
