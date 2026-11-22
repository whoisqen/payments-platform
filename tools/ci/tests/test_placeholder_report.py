import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import placeholder_report as pr  # noqa: E402


class PlaceholderReportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def test_finds_placeholders_in_scanned_dirs_only(self):
        self.write("deploy/a/values.yaml", "x: 1\nname: REPLACE_NAME\n")
        self.write("infra/live/b/main.hcl", "k = \"REPLACE_KEY\"\n")
        self.write("infra/modules/c.tf", "REPLACE_IGNORED\n")
        found = pr.scan(self.root)
        self.assertEqual(found, [("deploy/a/values.yaml", 2, "REPLACE_NAME"), ("infra/live/b/main.hcl", 1, "REPLACE_KEY")])

    def test_missing_dirs_and_exit_code_is_zero_with_findings(self):
        self.assertEqual(pr.scan(self.root), [])
        self.write("deploy/x.yaml", "REPLACE_A REPLACE_B\n")
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = pr.main([str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("2 REPLACE_ placeholders", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
