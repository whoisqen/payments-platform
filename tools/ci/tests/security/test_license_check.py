import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "security"))
import license_check as lc  # noqa: E402

POLICY = lc.Policy(["MIT", "Apache-2.0", "Apache-2.0 WITH LLVM-exception", "ISC"], ["GPL-3.0-only", "GPL-3.0", "AGPL-3.0-only"])


class EvaluateTest(unittest.TestCase):
    def test_leaves(self):
        self.assertEqual(lc.evaluate("MIT", POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate("mit", POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate("GPL-3.0-only", POLICY), lc.DENY)
        self.assertEqual(lc.evaluate("LGPL-2.1-only", POLICY), lc.REVIEW)

    def test_or_takes_the_best(self):
        self.assertEqual(lc.evaluate("MIT OR GPL-3.0-only", POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate("MIT/Apache-2.0", POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate("GPL-3.0-only OR AGPL-3.0-only", POLICY), lc.DENY)
        self.assertEqual(lc.evaluate("LGPL-2.1-only OR GPL-3.0-only", POLICY), lc.REVIEW)

    def test_and_takes_the_worst(self):
        self.assertEqual(lc.evaluate("MIT AND ISC", POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate("MIT AND GPL-3.0-only", POLICY), lc.DENY)
        self.assertEqual(lc.evaluate("(MIT OR Apache-2.0) AND GPL-3.0", POLICY), lc.DENY)
        self.assertEqual(lc.evaluate("(MIT OR GPL-3.0) AND ISC", POLICY), lc.ALLOW)

    def test_with_exception(self):
        self.assertEqual(lc.evaluate("Apache-2.0 WITH LLVM-exception", POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate("GPL-3.0-only WITH Classpath-exception-2.0", POLICY), lc.DENY)

    def test_malformed_is_unknown(self):
        for expr in ("", "MIT OR", "(MIT", "MIT)", "AND MIT", "MIT WITH"):
            self.assertEqual(lc.evaluate(expr, POLICY), lc.UNKNOWN, expr)


class InputsTest(unittest.TestCase):
    def test_cyclonedx_entries_are_alternatives(self):
        doc = {"components": [
            {"name": "a", "version": "1", "licenses": [{"license": {"id": "MIT"}}, {"license": {"id": "GPL-3.0-only"}}]},
            {"name": "b", "version": "2", "licenses": [{"expression": "MIT AND GPL-3.0-only"}]},
            {"name": "c", "version": "3"},
        ]}
        got = dict(lc.from_cyclonedx(doc))
        self.assertEqual(lc.evaluate(got["a@1"], POLICY), lc.ALLOW)
        self.assertEqual(lc.evaluate(got["b@2"], POLICY), lc.DENY)
        self.assertEqual(got["c@3"], "")

    def test_cargo_metadata_skips_workspace_crates(self):
        doc = {"packages": [
            {"name": "router", "version": "0.1.0", "license": None, "source": None},
            {"name": "serde", "version": "1.0.0", "license": "MIT OR Apache-2.0", "source": "registry+https://github.com/rust-lang/crates.io-index"},
        ]}
        self.assertEqual(list(lc.from_cargo_metadata(doc)), [("serde@1.0.0", "MIT OR Apache-2.0")])


class MainTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        (self.dir / "policy.toml").write_text('allow = ["MIT"]\ndeny = ["GPL-3.0-only"]\ndeny_aliases = ["GPL-3.0"]\n')

    def run_main(self, packages):
        meta = self.dir / "meta.json"
        meta.write_text(json.dumps({"packages": [
            {"name": n, "version": "1", "license": lic, "source": "registry"} for n, lic in packages
        ]}))
        out = io.StringIO()
        summary = self.dir / "summary.md"
        with redirect_stdout(out):
            code = lc.main(["--policy", str(self.dir / "policy.toml"), "--cargo-metadata", str(meta), "--summary", str(summary)])
        return code, out.getvalue(), summary.read_text()

    def test_denied_alias_fails(self):
        code, out, summary = self.run_main([("ok", "MIT"), ("bad", "GPL-3.0")])
        self.assertEqual(code, 1)
        self.assertIn("::error::bad@1", out)
        self.assertIn("denied 1", summary)

    def test_review_and_unknown_do_not_fail(self):
        code, _, summary = self.run_main([("ok", "MIT"), ("weak", "LGPL-2.1-only"), ("none", None)])
        self.assertEqual(code, 0)
        self.assertIn("review 1, no license 1, denied 0", summary)


if __name__ == "__main__":
    unittest.main()
