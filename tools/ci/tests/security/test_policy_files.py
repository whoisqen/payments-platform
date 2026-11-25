import re
import sys
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SEC = ROOT / "policy/security"
sys.path.insert(0, str(ROOT / "tools/ci/security"))
import gates  # noqa: E402

try:
    import yaml
except ImportError:
    yaml = None


def toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


class LicenseListsTest(unittest.TestCase):
    def test_cargo_deny_allows_the_same_licenses(self):
        self.assertEqual(sorted(toml(SEC / "deps/deny.toml")["licenses"]["allow"]), sorted(toml(SEC / "deps/licenses.toml")["allow"]))

    def test_allow_and_deny_do_not_overlap(self):
        conf = toml(SEC / "deps/licenses.toml")
        self.assertFalse({x.lower() for x in conf["allow"]} & {x.lower() for x in conf["deny"] + conf["deny_aliases"]})

    @unittest.skipUnless(yaml, "pyyaml is not installed")
    def test_dependency_review_denies_the_same_licenses(self):
        conf = yaml.safe_load((SEC / "deps/dependency-review.yml").read_text())
        self.assertEqual(sorted(conf["deny-licenses"]), sorted(toml(SEC / "deps/licenses.toml")["deny"]))


class WaiversTest(unittest.TestCase):
    def test_every_checkov_skip_has_a_reason(self):
        lines = (SEC / "iac/checkov.yaml").read_text().splitlines()
        start = next(i for i, line in enumerate(lines) if line.startswith("skip-check:"))
        if lines[start].strip() == "skip-check: []":
            return
        for line in lines[start + 1:]:
            if not line.startswith("  "):
                break
            self.assertRegex(line, r"^\s+- [A-Z0-9_]+\s+#\s*\S", f"checkov skip without a reason: {line!r}")

    @unittest.skipUnless(yaml, "pyyaml is not installed")
    def test_every_trivy_waiver_has_a_statement(self):
        conf = yaml.safe_load((SEC / "trivyignore.yaml").read_text()) or {}
        for kind, entries in conf.items():
            for e in entries or []:
                self.assertTrue(str(e.get("statement", "")).strip(), f"{kind} waiver {e.get('id')} has no statement")

    def test_zap_rules_are_well_formed(self):
        for line in (SEC / "dast/zap-rules.tsv").read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            self.assertRegex(line, r"^\d+\t(IGNORE|WARN|FAIL)\t\S", f"malformed ZAP rule: {line!r}")


class GatesTest(unittest.TestCase):
    def test_semgrep_runs_the_repo_rules_and_blocks_on_error(self):
        conf = toml(SEC / "code/semgrep.toml")
        self.assertIn("policy/semgrep", conf["configs"])
        self.assertIn("error", conf["block_levels"])
        self.assertIn("policy/semgrep", conf["exclude"])

    def test_zizmor_threshold_is_a_known_severity(self):
        self.assertIn(gates.get(toml(SEC / "workflows/zizmor-gate.toml"), "min_severity")[0], {"informational", "low", "medium", "high"})

    def test_trivy_gates_block_high_and_critical(self):
        for f in ("iac/trivy-config.yaml", "deps/trivy-vuln.yaml"):
            text = (SEC / f).read_text()
            self.assertRegex(text, r"(?m)^exit-code: 1$", f)
            self.assertTrue(re.search(r"- HIGH", text) and re.search(r"- CRITICAL", text), f)


if __name__ == "__main__":
    unittest.main()
