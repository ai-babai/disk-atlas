"""Execute the native maintenance tools on temporary files, with real LLVM profiles."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.quality import swift_tools


class NativeScriptTests(unittest.TestCase):
    def invoke(self, name, *arguments):
        binary = swift_tools.binary(name, profiled=True)
        return subprocess.run([str(binary), *map(str, arguments)], text=True, capture_output=True)

    def test_icon_generation_preserves_neighboring_iconsets(self):
        with tempfile.TemporaryDirectory(prefix="atlas icon Ю ") as directory:
            output = Path(directory)
            neighbor = output / "AppIcon.iconset"
            neighbor.mkdir()
            sentinel = neighbor / "user-file"
            sentinel.write_text("preserve")
            result = self.invoke("icon", output)
            self.assertEqual(result.returncode, 0, result.stderr)
            icon = output / "AppIcon.icns"
            data = icon.read_bytes()
            self.assertEqual(data[:4], b"icns")
            self.assertEqual(int.from_bytes(data[4:8], "big"), len(data))
            self.assertGreater(len(data), 1000)
            self.assertEqual(sentinel.read_text(), "preserve")
            self.assertEqual(sorted(path.name for path in output.iterdir()), ["AppIcon.icns", "AppIcon.iconset"])
            occupied = output / "file"
            occupied.touch()
            self.assertEqual(self.invoke("icon", occupied).returncode, 1)
        self.assertEqual(self.invoke("icon").returncode, 2)

    def test_swift_syntax_variants_and_errors(self):
        source = """
struct S {
    init() { if true {} }
    var computed: Int { return 1 }
    func branches(_ a: Bool, _ b: Bool) {
        func nested() { if a {} }
        if a {} else if b {} else {}
        guard a else { return }
        for _ in 0...2 { while a { break } }
        repeat {} while false
        do { try perform() } catch { print(error) }
        let value = a ? 1 : 2
        switch value { case 1: break; default: break }
        let block = { if a && b || a { print(value) } }
        block()
    }
}
class C { func f() {} }
enum E { func f() {} }
actor A { func f() {} }
extension S { func extended() {} }
protocol P { func abstract() }
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.swift"
            path.write_text(source)
            result = self.invoke("metrics", path)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = json.loads(result.stdout)
            identities = [row["identity"] for row in rows]
            self.assertIn("S.property:computed", identities)
            self.assertIn("S.extended()", identities)
            self.assertIn("A.f()", identities)
            self.assertGreater(max(row["cyclomatic"] for row in rows), 10)
            self.assertEqual(len(rows), 8)
            path.write_text("func broken( {")
            self.assertEqual(self.invoke("metrics", path).returncode, 1)
            self.assertEqual(self.invoke("metrics", path / "missing").returncode, 1)
        self.assertEqual(json.loads(self.invoke("metrics").stdout), [])


if __name__ == "__main__":
    unittest.main()
