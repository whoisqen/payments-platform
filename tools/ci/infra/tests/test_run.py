import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import applied_base as ab  # noqa: E402
import run  # noqa: E402

CFG = {"accounts": {"shared_services": "222222222222"}, "naming": {"prefix": "pay"}}
SHA = "a" * 40
VPC, EKS, KMS = "infra/live/stage/euc/vpc", "infra/live/stage/euc/cell-0/eks", "infra/live/stage/euc/kms"
DOC = {"env": "stage", "levels": [[KMS, VPC], [EKS]], "deps": {KMS: [], VPC: [], EKS: [VPC]}}


class Fake:
    def __init__(self, plan_codes, fail_apply=()):
        self.plan_codes, self.fail_apply, self.calls = plan_codes, set(fail_apply), []

    def __call__(self, cmd, env, out_path):
        stack, verb = cmd[4], cmd[6]
        self.calls.append((verb, stack, env["AWS_ROLE_ARN"]))
        body = "Plan: 1 to add, 0 to change, 2 to destroy.\n" if verb == "show" else f"{verb} {stack}\n"
        Path(out_path).write_text(body, encoding="utf-8")
        if verb == "plan":
            Path(cmd[-1].split("=", 1)[1]).write_text("binary", encoding="utf-8")
            return self.plan_codes.get(stack, 0)
        if verb == "apply":
            return 1 if stack in self.fail_apply else 0
        return 0


class RunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def runner(self, fake):
        return run.Runner(self.dir, fetch_token=lambda: "token", execute=fake, parallel=2, log=lambda *_: None)

    def test_role_names_follow_the_bootstrap_roles(self):
        self.assertEqual(run.role_arn(CFG, "prod", "plan"), "arn:aws:iam::222222222222:role/pay-prod-glob-tf-plan")
        self.assertEqual(run.role_arn(CFG, "prod", "apply", EKS), "arn:aws:iam::222222222222:role/pay-prod-glob-tf-apply-eks")

    def test_gated_plan_uses_the_plan_role_and_defers_behind_a_changed_upstream(self):
        fake = Fake({VPC: 2, KMS: 0})
        m = run.plan(self.runner(fake), CFG, DOC, self.dir / "plan", SHA)
        self.assertEqual(m["status"], {KMS: "none", VPC: "changes", EKS: "deferred"})
        self.assertTrue(all(c[2].endswith("tf-plan") for c in fake.calls))
        self.assertNotIn(("plan", EKS), [(c[0], c[1]) for c in fake.calls])
        self.assertEqual(run.outcome(m), {"changes": True, "deferred": True, "failed": False})

    def test_downstream_of_an_unchanged_upstream_is_planned(self):
        m = run.plan(self.runner(Fake({EKS: 2})), CFG, DOC, self.dir / "plan", SHA)
        self.assertEqual(m["status"][EKS], "changes")

    def test_apply_now_applies_each_level_before_the_next_plan(self):
        fake = Fake({VPC: 2, EKS: 2})
        m = run.plan(self.runner(fake), CFG, DOC, self.dir / "plan", SHA, apply_now=True)
        verbs = [(c[0], c[1]) for c in fake.calls if c[0] != "show"]
        self.assertLess(verbs.index(("apply", VPC)), verbs.index(("plan", EKS)))
        self.assertEqual(m["status"][EKS], "applied")
        self.assertTrue(all("tf-apply-" in c[2] for c in fake.calls))

    def test_a_failed_level_stops_the_run(self):
        m = run.plan(self.runner(Fake({VPC: 1})), CFG, DOC, self.dir / "plan", SHA)
        self.assertEqual(m["status"][VPC], "failed")
        self.assertNotIn(EKS, m["status"])

    def test_apply_uses_the_reviewed_plan_of_the_same_commit(self):
        run.plan(self.runner(Fake({VPC: 2})), CFG, DOC, self.dir / "plan", SHA)
        fake = Fake({})
        m = run.apply(self.runner(fake), CFG, self.dir / "plan", SHA)
        self.assertEqual([(c[0], c[1]) for c in fake.calls], [("apply", VPC)])
        self.assertTrue(fake.calls[0][2].endswith("tf-apply-vpc"))
        self.assertEqual(m["status"][VPC], "applied")
        with self.assertRaises(run.RunError):
            run.apply(self.runner(Fake({})), CFG, self.dir / "plan", "b" * 40)

    def test_missing_plan_file_fails_before_any_apply(self):
        run.plan(self.runner(Fake({VPC: 2})), CFG, DOC, self.dir / "plan", SHA)
        (self.dir / "plan" / run.plan_file(VPC)).unlink()
        fake = Fake({})
        with self.assertRaises(run.RunError):
            run.apply(self.runner(fake), CFG, self.dir / "plan", SHA)
        self.assertEqual(fake.calls, [])

    def test_static_credentials_never_reach_terragrunt(self):
        import os

        os.environ["AWS_ACCESS_KEY_ID"] = "x"
        try:
            env = self.runner(Fake({})).env_for("arn:aws:iam::1:role/r", VPC)
        finally:
            del os.environ["AWS_ACCESS_KEY_ID"]
        self.assertNotIn("AWS_ACCESS_KEY_ID", env)
        self.assertEqual(Path(env["AWS_WEB_IDENTITY_TOKEN_FILE"]).read_text(), "token")

    def test_summary_lists_every_stack(self):
        m = run.plan(self.runner(Fake({VPC: 2})), CFG, DOC, self.dir / "plan", SHA)
        text = run.summary(m, "t")
        self.assertIn(f"| `{EKS}` | deferred |", text)
        self.assertIn(f"| `{VPC}` | changes | Plan: 1 to add, 0 to change, 2 to destroy. |", text)
        self.assertTrue((self.dir / "plan" / (run.plan_file(VPC) + ".txt")).is_file())
        self.assertEqual(json.loads((self.dir / "plan" / "manifest.json").read_text())["sha"], SHA)


class AppliedBaseTest(unittest.TestCase):
    def jobs(self, table):
        return lambda run_id: [{"name": n, "conclusion": c} for n, c in table[run_id].items()]

    def test_newest_converged_push_run(self):
        runs = [
            {"id": 3, "event": "push", "status": "completed", "head_sha": "c" * 40},
            {"id": 2, "event": "push", "status": "completed", "head_sha": "b" * 40},
            {"id": 1, "event": "push", "status": "completed", "head_sha": "a" * 40},
        ]
        jobs = {3: {"stage / plan": "success", "stage / apply": "failure"},
                2: {"stage / plan": "success", "stage / apply": "skipped"},
                1: {"stage / plan": "success", "stage / apply": "success"}}
        self.assertEqual(ab.find_base(runs, self.jobs(jobs), "stage", lambda s: True), "b" * 40)

    def test_dispatch_runs_and_lost_commits_never_count(self):
        runs = [{"id": 2, "event": "workflow_dispatch", "status": "completed", "head_sha": "b" * 40},
                {"id": 1, "event": "push", "status": "completed", "head_sha": "a" * 40}]
        jobs = {2: {"dev / plan": "success"}, 1: {"dev / plan": "success"}}
        self.assertIsNone(ab.find_base(runs, self.jobs(jobs), "dev", lambda s: False))

    def test_skipped_environment_is_not_converged(self):
        self.assertFalse(ab.converged([{"name": "dev / plan", "conclusion": "success"}], "prod"))
        self.assertFalse(ab.converged([{"name": "prod / plan", "conclusion": "failure"}], "prod"))


if __name__ == "__main__":
    unittest.main()
