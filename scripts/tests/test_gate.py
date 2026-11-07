import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.quality import coverage_audit, mutations, source_audit, swift_audit
from scripts.quality.common import ROOT


class GateTests(unittest.TestCase):
    def test_parser_ignores_comments_strings_and_separates_functions(self):
        source = """
        func first(a: Bool, b: Bool) {
            let text = "if for while switch"
            // if a { while b {} }
            if a { while b { break } }
        }
        func second() { print("catch else") }
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.swift"
            path.write_text(source)
            rows = swift_audit.metrics([path])
        self.assertEqual([(r["cyclomatic"], r["cognitive"]) for r in rows], [(3, 3), (1, 0)])

    def test_format_only_bodies_keep_the_same_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.swift"
            second = Path(directory) / "second.swift"
            first.write_text("func f() -> Int { return 1 }")
            second.write_text("func f() -> Int { // if while\n return 1; }")
            self.assertEqual(swift_audit.metrics([first])[0]["bodyHash"], swift_audit.metrics([second])[0]["bodyHash"])

    def test_mutation_compile_and_environment_failures_are_not_kills(self):
        assertion = "Build complete!\nfile.swift:2: error: test : XCTAssertEqual failed: wrong order"
        self.assertTrue(mutations.detected(1, assertion))
        self.assertFalse(mutations.detected(0, assertion))
        self.assertFalse(mutations.detected(1, "file.swift:2: error: cannot compile"))
        self.assertFalse(mutations.detected(1, "Build complete!\nTest Suite started\nunexpected signal 6"))

    def test_changed_body_cannot_use_legacy_exception(self):
        row = dict(file="example.swift", identity="f()", start=1, cyclomatic=12, cognitive=16, bodyHash="old")
        legacy = {coverage_audit.identity(row): row.copy()}
        policy = dict(cyclomatic_max=10, cognitive_max=15)
        self.assertEqual(len(source_audit.complexity_failures([row], legacy, policy)[1]), 1)
        row["bodyHash"] = "changed"
        self.assertEqual(len(source_audit.complexity_failures([row], legacy, policy)[0]), 1)

    def test_lcov_uses_actual_line_counts_and_missing_coverage_fails(self):
        lines = swift_audit.lcov_lines(
            "SF:" + str(ROOT / "Sources/AtlasCore/example.swift") + "\nDA:2,3\nDA:3,0\nend_of_record\n"
        )
        self.assertEqual(lines["Sources/AtlasCore/example.swift"], {2: 3, 3: 0})
        row = dict(file="Sources/AtlasCore/example.swift", identity="f()", start=2, end=3, cyclomatic=2, bodyHash="new")
        policy = dict(coverage_min=80, crap_average_below=5, crap_max=30)
        with patch.object(coverage_audit, "added_lines", return_value={2, 3}):
            result, errors = coverage_audit.measure([row], {}, lines, "unused", policy)
            self.assertEqual(result["percent"], 50)
            self.assertTrue(errors)
            self.assertTrue(coverage_audit.measure([row], {}, {}, "unused", policy)[1])


if __name__ == "__main__":
    unittest.main()
