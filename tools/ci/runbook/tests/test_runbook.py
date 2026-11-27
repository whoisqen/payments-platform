import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import runbook as rb  # noqa: E402

CFG = {"accounts": {"dev": "111111111111", "stage": "333333333333", "prod": "444444444444"}, "naming": {"prefix": "pay"}}
CAT = rb.catalog()


class CatalogTest(unittest.TestCase):
    def test_every_documented_alert_maps_to_its_document(self):
        self.assertEqual(CAT[0]["PSPDegraded"], "pay-runbook-psp-degraded")
        self.assertEqual(CAT[0]["Watchdog"], "pay-runbook-watchdog")
        self.assertEqual(set(CAT[0].values()), set(CAT[1]))

    def test_steps_stay_inside_their_section(self):
        self.assertEqual(CAT[1]["pay-runbook-watchdog"]["steps"], {"restart-alert-pipeline"})
        self.assertEqual(CAT[1]["pay-runbook-root-account-login"]["steps"], set())


class RequestTest(unittest.TestCase):
    def test_diagnose_uses_the_read_only_roles_of_the_environment(self):
        r = rb.diagnose(CAT, CFG, "PSPDegraded", "prod", "eu-central-1")
        self.assertEqual(r["mode"], "diagnose")
        self.assertEqual(r["role"], "arn:aws:iam::444444444444:role/pay-prod-glob-runbook-diagnose")
        self.assertEqual(r["execution_role"], "arn:aws:iam::444444444444:role/pay-prod-glob-runbook-diagnose-exec")

    def test_unknown_alert_environment_or_region_fails(self):
        for args in (("NoSuchAlert", "prod", "eu-central-1"), ("PSPDegraded", "cde-prod", "eu-central-1"),
                     ("PSPDegraded", "prod", "eu-west-1"), ("PSPDegraded;id", "prod", "eu-central-1")):
            with self.assertRaises(rb.RunbookError, msg=args):
                rb.diagnose(CAT, CFG, *args)

    def test_action_needs_a_named_step_when_the_runbook_names_one(self):
        r = rb.action(CAT, CFG, "pay-runbook-psp-degraded", "route-away-psp", "stage", "eu-central-1")
        self.assertEqual((r["mode"], r["step"]), ("act", "route-away-psp"))
        self.assertTrue(r["role"].endswith("pay-stage-glob-runbook-actions"))
        for step in ("", "delete-everything"):
            with self.assertRaises(rb.RunbookError):
                rb.action(CAT, CFG, "pay-runbook-psp-degraded", step, "stage", "eu-central-1")

    def test_action_without_named_steps_takes_no_step(self):
        self.assertEqual(rb.action(CAT, CFG, "pay-runbook-root-account-login", "", "prod", "eu-central-1")["step"], "")
        with self.assertRaises(rb.RunbookError):
            rb.action(CAT, CFG, "pay-runbook-root-account-login", "x", "prod", "eu-central-1")
        with self.assertRaises(rb.RunbookError):
            rb.action(CAT, CFG, "pay-runbook-nope", "", "prod", "eu-central-1")


class SsmRunTest(unittest.TestCase):
    def run_script(self, request):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "request.json"
            p.write_text(json.dumps(request), encoding="utf-8")
            env = {k: v for k, v in os.environ.items() if k != "GITHUB_STEP_SUMMARY"}
            return subprocess.run([str(HERE / "ssm-run.sh"), "--dry-run", str(p)], capture_output=True, text=True, env=env)

    def test_dry_run_passes_the_execution_role_and_step(self):
        req = rb.action(CAT, CFG, "pay-runbook-psp-degraded", "route-away-psp", "dev", "eu-central-1")
        out = self.run_script(req)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn('"Step":["route-away-psp"]', out.stdout)
        self.assertIn("pay-dev-glob-runbook-actions-exec", out.stdout)

    def test_tampered_request_is_refused(self):
        req = rb.diagnose(CAT, CFG, "PSPDegraded", "dev", "eu-central-1")
        self.assertNotEqual(self.run_script({**req, "document": "AWS-RunShellScript"}).returncode, 0)
        self.assertNotEqual(self.run_script({**req, "step": "x; rm"}).returncode, 0)


if __name__ == "__main__":
    unittest.main()
