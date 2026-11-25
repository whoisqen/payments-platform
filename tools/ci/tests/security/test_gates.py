import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "security"))
import gates  # noqa: E402


def sarif(results, rules=()):
    return {"runs": [{"tool": {"driver": {"name": "t", "rules": list(rules)}}, "results": results}]}


def result(rule, level=None, path="a.rs", line=3):
    r = {"ruleId": rule, "locations": [{"physicalLocation": {"artifactLocation": {"uri": path}, "region": {"startLine": line}}}]}
    if level:
        r["level"] = level
    return r


class SarifGateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def gate(self, doc, levels=("error",)):
        f = self.dir / "r.sarif"
        f.write_text(json.dumps(doc))
        out = io.StringIO()
        return gates.sarif_gate({"block_levels": list(levels)}, [f], out=out), out.getvalue()

    def test_error_blocks(self):
        code, out = self.gate(sarif([result("no-pan-logging", "error"), result("x", "warning")]))
        self.assertEqual(code, 1)
        self.assertIn("::error::a.rs:3 no-pan-logging", out)
        self.assertIn("1 error, 1 warning", out)

    def test_warning_and_note_only_report(self):
        code, _ = self.gate(sarif([result("x", "warning"), result("y", "note")]))
        self.assertEqual(code, 0)

    def test_level_falls_back_to_rule_default(self):
        rules = [{"id": "r", "defaultConfiguration": {"level": "error"}}]
        self.assertEqual(self.gate(sarif([result("r")], rules))[0], 1)
        self.assertEqual(self.gate(sarif([result("other")], rules))[0], 0)

    def test_empty_report_passes(self):
        self.assertEqual(self.gate({"runs": []})[0], 0)


class ConfigTest(unittest.TestCase):
    def test_semgrep_args(self):
        args = gates.semgrep_args({"configs": ["policy/semgrep", "p/rust"], "exclude": ["vendor/x"]})
        self.assertEqual(args, ["--config", "policy/semgrep", "--config", "p/rust", "--exclude", "vendor/x"])

    def test_get_scalar_and_list(self):
        self.assertEqual(gates.get({"min_severity": "high"}, "min_severity"), ["high"])
        self.assertEqual(gates.get({"block_levels": ["error", "warning"]}, "block_levels"), ["error", "warning"])


if __name__ == "__main__":
    unittest.main()
