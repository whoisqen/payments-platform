import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("compute_build", Path(__file__).resolve().parents[1] / "compute_build.py")
cb = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cb)

CELLS = ("cell-0", "spare")


def tree(root):
    (root / "config").mkdir()
    (root / "config/platform.yaml").write_text("project: x\nnaming:\n  # comment\n  prefix: pay\n\nregistry:\n  prefix: other\nvault:\n  # comment\n  cell: cell-0\n")
    for cell in CELLS:
        for unit in cb.UNITS + ("aurora",):
            d = root / "infra/live/prod/us-east-1" / cell / unit
            d.mkdir(parents=True)
            (d / "terragrunt.hcl").write_text(f'inputs = {{\n  component           = "{unit}-{cell}"\n}}\n')
    (root / "infra/live/prod/us-east-1/kms").mkdir()
    (root / "deploy/argocd/templates/addons").mkdir(parents=True)
    (root / "deploy/argocd/templates/addons/argocd.yaml").write_text("      sources:\n        - repoURL: https://argoproj.github.io/argo-helm\n"
                                                                    "          chart: argo-cd\n          targetRevision: 10.18.2\n")


class Runner:
    def __init__(self, fail=(), healthy_after=1):
        self.lock, self.calls, self.fail, self.healthy_after = threading.Lock(), [], set(fail), healthy_after

    def __call__(self, cmd, **kw):
        with self.lock:
            self.calls.append((cmd, kw))
        if cmd[0] == "terragrunt":
            unit = "/".join(Path(cmd[cmd.index("--working-dir") + 1]).parts[-2:])
            return subprocess.CompletedProcess(cmd, 1 if unit in self.fail else 0, "", "")
        if cmd[:3] == ["helm", "get", "values"]:
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"pilotLight": [{"environment": "stage", "region": "us-east-1"},
                                                                               {"environment": "prod", "region": "us-east-1"}]}), "")
        if cmd[0] == sys.executable:
            return subprocess.CompletedProcess(cmd, 0, "repo:\n  url: x\ngated:\n  revision: ''\npilotLight:\n- {environment: stage, region: us-east-1}\n"
                                                       "- {environment: prod, region: us-east-1}\n", "")
        if cmd[:2] == ["git", "tag"]:
            return subprocess.CompletedProcess(cmd, 0, "v1.4.0\nv1.3.9\n", "")
        if cmd[:3] == ["kubectl", "get", "applications.argoproj.io"]:
            self.polls = getattr(self, "polls", 0) + 1
            health = "Healthy" if self.polls >= self.healthy_after else "Progressing"
            items = [{"metadata": {"name": f"payments-cell-{env}-us-east-1-cell-0"}, "status": {"sync": {"status": "Synced"}, "health": {"status": health}}}
                     for env in ("prod", "stage")] + [{"metadata": {"name": "payments-cell-stage-eu-central-1-cell-0"}, "status": {}}]
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"items": items}), "")
        if cmd[:3] == ["aws", "eks", "describe-cluster"]:
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"cluster": {"endpoint": "https://e", "certificateAuthority": {"data": "Q0E="}}}), "")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    def applied(self):
        return ["/".join(Path(c[c.index("--working-dir") + 1]).parts[-2:]) for c, _ in self.calls if c[0] == "terragrunt"]


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        tree(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def main(self, args, runner, env="prod"):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = cb.main(args + ["--env", env, "--region", "us-east-1", "--root", str(self.root)], run=runner, sleep=lambda s: None)
        return code, out.getvalue()


class ComputeBuildTest(Base):
    def test_applies_the_four_units_of_every_cell_with_the_standby_flag(self):
        runner = Runner()
        code, out = self.main(["apply"], runner)
        self.assertEqual(code, 0)
        self.assertEqual(sorted(runner.applied()), sorted(f"{c}/{u}" for c in CELLS for u in cb.UNITS))
        self.assertTrue(all(kw["env"]["PAY_STANDBY_COMPUTE"] == "true" for c, kw in runner.calls))
        self.assertTrue(all(c[-2:] == ["-input=false", "-auto-approve"] for c, _ in runner.calls))
        self.assertIn('"event": "compute-built"', out)

    def test_dependency_order_inside_a_cell(self):
        runner = Runner()
        self.main(["apply"], runner)
        for cell in CELLS:
            order = [u.split("/")[1] for u in runner.applied() if u.startswith(cell + "/")]
            self.assertLess(order.index("eks"), order.index("karpenter"))
            self.assertEqual(order[-1], "iam-workloads")

    def test_a_failed_unit_fails_the_build_and_stops_its_dependents(self):
        runner = Runner(fail={"cell-0/eks"})
        code, out = self.main(["apply"], runner)
        self.assertEqual(code, 1)
        self.assertNotIn("cell-0/karpenter", runner.applied())
        self.assertNotIn("cell-0/iam-workloads", runner.applied())
        self.assertIn("spare/iam-workloads", runner.applied())
        self.assertIn('"failed": ["cell-0"]', out)

    def test_dry_run_runs_nothing(self):
        runner, out = Runner(), ""
        for action in ("apply", "register"):
            code, text = self.main([action, "--dry-run"], runner)
            self.assertEqual(code, 0)
            out += text
        self.assertEqual(runner.calls, [])
        self.assertEqual(out.count('"event": "would-apply"'), len(CELLS) * len(cb.UNITS))
        self.assertIn('"name": "pay-prod-use1-spare"', out)

    def test_register_writes_the_argocd_cluster_secret(self):
        runner = Runner()
        code, _ = self.main(["register", "--argocd-role-arn", "arn:aws:iam::1:role/argocd"], runner)
        self.assertEqual(code, 0)
        described = [c for c, _ in runner.calls if c[:3] == ["aws", "eks", "describe-cluster"]]
        self.assertEqual(described[0][described[0].index("--name") + 1], "pay-prod-use1-eks-cell-0")
        doc = json.loads(next(kw["input"] for c, kw in runner.calls if c[0] == "kubectl"))
        self.assertEqual(doc["metadata"]["labels"]["argocd.argoproj.io/secret-type"], "cluster")
        self.assertEqual(doc["metadata"]["labels"]["payments-platform/region"], "us-east-1")
        self.assertEqual(doc["metadata"]["labels"]["payments-platform/vault"], "enabled")
        spare = [json.loads(kw["input"]) for c, kw in runner.calls if c[0] == "kubectl"][1]
        self.assertNotIn("payments-platform/vault", spare["metadata"]["labels"])
        self.assertEqual(doc["stringData"]["name"], "pay-prod-use1-cell-0")
        config = json.loads(doc["stringData"]["config"])
        self.assertEqual(config["awsAuthConfig"], {"clusterName": "pay-prod-use1-eks-cell-0", "roleARN": "arn:aws:iam::1:role/argocd"})
        self.assertEqual(config["tlsClientConfig"]["caData"], "Q0E=")

    def test_rejects_dev_and_odd_regions(self):
        for args in (["apply", "--env", "dev", "--region", "us-east-1"], ["apply", "--env", "prod", "--region", "x; rm"]):
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                cb.parse_args(args)


    def test_register_opens_only_this_region_in_the_argocd_release(self):
        runner = Runner()
        code, _ = self.main(["register", "--apps-release", "platform"], runner)
        self.assertEqual(code, 0)
        upgrade = next(c for c, _ in runner.calls if c[:2] == ["helm", "upgrade"])
        self.assertIn("--reuse-values", upgrade)
        self.assertEqual(upgrade[-1], 'pilotLight=[{"environment": "stage", "region": "us-east-1"}]')
        kubectl = max(i for i, (c, _) in enumerate(runner.calls) if c[0] == "kubectl")
        self.assertLess(kubectl, next(i for i, (c, _) in enumerate(runner.calls) if c[:2] == ["helm", "upgrade"]))

    def test_no_upgrade_when_the_region_is_already_open(self):
        runner = OpenRegion()
        code, out = self.main(["register", "--apps-release", "platform"], runner)
        self.assertEqual(code, 0)
        self.assertFalse(any(c[:2] == ["helm", "upgrade"] for c, _ in runner.calls))
        self.assertIn("skip-open-region", out)


    def test_state_region_is_exported_only_when_asked(self):
        runner = Runner()
        self.main(["apply", "--state-region", "us-east-1"], runner)
        self.assertTrue(all(kw["env"]["PAY_STATE_REGION"] == "us-east-1" for _, kw in runner.calls))
        runner = Runner()
        self.main(["apply"], runner)
        self.assertFalse(any("PAY_STATE_REGION" in kw["env"] for _, kw in runner.calls))

    @unittest.skipUnless(importlib.util.find_spec("yaml"), "PyYAML is not installed")
    def test_argocd_core_installs_into_the_first_standby_cluster(self):
        runner = Runner()
        code, out = self.main(["argocd-core", "--argocd-controller-role-arn", "arn:aws:iam::1:role/argocd-core"], runner)
        self.assertEqual(code, 0)
        cmds = [c for c, _ in runner.calls if c[0] in ("aws", "helm")]
        self.assertEqual(cmds[0][cmds[0].index("--name") + 1], "pay-prod-use1-eks-cell-0")
        self.assertEqual(cmds[1][cmds[1].index("--version") + 1], "10.18.2")
        core = json.loads(next(kw["input"] for c, kw in runner.calls if c[:4] == ["helm", "upgrade", "--install", "argocd"]))
        self.assertEqual((core["server"]["replicas"], core["dex"]["enabled"]), (0, False))
        self.assertEqual(core["controller"]["serviceAccount"]["annotations"]["eks.amazonaws.com/role-arn"], "arn:aws:iam::1:role/argocd-core")
        apps = json.loads(next(kw["input"] for c, kw in runner.calls if c[:4] == ["helm", "upgrade", "--install", "platform-apps"]))
        self.assertEqual(apps["pilotLight"], [{"environment": "stage", "region": "us-east-1"}])
        self.assertEqual(apps["gated"]["revision"], "v1.4.0")

    def test_wait_apps_until_the_region_is_healthy(self):
        runner = Runner(healthy_after=3)
        code, out = self.main(["wait-apps"], runner, env="stage")
        self.assertEqual(code, 0)
        self.assertEqual(runner.polls, 3)
        self.assertIn('"apps": ["payments-cell-stage-us-east-1-cell-0"]', out)

    def test_wait_apps_gives_up_at_the_deadline(self):
        runner = Runner(healthy_after=10**6)
        code, out = self.main(["wait-apps", "--wait-minutes", "0"], runner, env="stage")
        self.assertEqual(code, 1)
        self.assertIn("apps-not-ready", out)

    def test_wait_apps_only_checks_presence_for_gated_prod(self):
        runner = Runner(healthy_after=10**6)
        code, out = self.main(["wait-apps"], runner)
        self.assertEqual(code, 0)
        self.assertIn("sync each cell by hand", out)


class OpenRegion(Runner):
    def __call__(self, cmd, **kw):
        if cmd[:3] == ["helm", "get", "values"]:
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"pilotLight": [{"environment": "stage", "region": "us-east-1"}]}), "")
        return super().__call__(cmd, **kw)

def app(name, rev="v1.4.0", sync="OutOfSync", health="Missing"):
    return {"metadata": {"name": name}, "spec": {"sources": [{"repoURL": "r", "targetRevision": rev}, {"repoURL": "r", "targetRevision": rev, "ref": "values"}]},
            "status": {"sync": {"status": sync}, "health": {"status": health}}}


class Argo(Runner):
    # Applications become healthy one poll after their sync was started, unless listed in stuck
    def __init__(self, apps, stuck=()):
        super().__init__()
        self.apps, self.stuck, self.synced = {a["metadata"]["name"]: a for a in apps}, set(stuck), []

    def __call__(self, cmd, **kw):
        if cmd[:3] == ["kubectl", "get", "applications.argoproj.io"]:
            with self.lock:
                self.calls.append((cmd, kw))
            for name in self.synced:
                if name not in self.stuck:
                    self.apps[name]["status"] = {"sync": {"status": "Synced"}, "health": {"status": "Healthy"}}
            return subprocess.CompletedProcess(cmd, 0, json.dumps({"items": list(self.apps.values())}), "")
        if cmd[:2] == ["kubectl", "patch"]:
            with self.lock:
                self.calls.append((cmd, kw))
            self.synced.append(cmd[3])
            return subprocess.CompletedProcess(cmd, 0, "", "")
        return super().__call__(cmd, **kw)


PROD = [f"payments-cell-prod-us-east-1-{c}" for c in ("spare", "cell-1", "cell-0")] + ["payments-locker-prod-us-east-1"]


class DrSyncTest(Base):
    def test_syncs_cell_by_cell_at_the_deployed_release(self):
        runner = Argo([app(n) for n in PROD] + [app("payments-cell-prod-eu-central-1-cell-0")])
        code, out = self.main(["wait-apps", "--dr-sync"], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.synced, ["payments-cell-prod-us-east-1-cell-0", "payments-cell-prod-us-east-1-cell-1",
                                         "payments-cell-prod-us-east-1-spare", "payments-locker-prod-us-east-1"])
        patch = json.loads(next(c for c, _ in runner.calls if c[:2] == ["kubectl", "patch"])[-1])
        self.assertNotIn("revision", patch["operation"]["sync"])
        self.assertIn("dr-sync-done", out)

    def test_an_unhealthy_cell_stops_the_later_cells(self):
        runner = Argo([app(n) for n in PROD], stuck={"payments-cell-prod-us-east-1-cell-0"})
        code, out = self.main(["wait-apps", "--dr-sync", "--wait-minutes", "0"], runner)
        self.assertEqual(code, 1)
        self.assertEqual(runner.synced, ["payments-cell-prod-us-east-1-cell-0"])
        self.assertIn("dr-sync-stopped", out)

    def test_refuses_an_application_not_pinned_to_the_release(self):
        runner = Argo([app(PROD[2]), app(PROD[1], rev="main")])
        code, out = self.main(["wait-apps", "--dr-sync"], runner)
        self.assertEqual(code, 1)
        self.assertEqual(runner.synced, [PROD[2]])
        self.assertIn("dr-sync-refused", out)

    def test_healthy_cells_are_not_synced_again(self):
        runner = Argo([app(n, sync="Synced", health="Healthy") for n in PROD])
        code, _ = self.main(["wait-apps", "--dr-sync"], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.synced, [])

    def test_without_dr_sync_prod_stays_manual(self):
        runner = Argo([app(n) for n in PROD])
        code, _ = self.main(["wait-apps"], runner)
        self.assertEqual(code, 0)
        self.assertEqual(runner.synced, [])


class ResolveStateTest(unittest.TestCase):
    def test_drill_defaults_to_working_and_rejects_replica(self):
        self.assertEqual(cb.resolve_state("drill", "auto", "", "prod"), "working")
        self.assertEqual(cb.resolve_state("drill", "working", "switch prod", "prod"), "working")
        with self.assertRaisesRegex(ValueError, "drill"):
            cb.resolve_state("drill", "replica", "switch prod", "prod")

    def test_switch_defaults_to_replica_and_needs_the_confirmation(self):
        self.assertEqual(cb.resolve_state("switch", "auto", "switch prod", "prod"), "replica")
        for confirm in ("", "switch stage", "yes"):
            with self.assertRaises(ValueError):
                cb.resolve_state("switch", "auto", confirm, "prod")
        with self.assertRaises(ValueError):
            cb.resolve_state("other", "auto", "", "prod")

    def test_cli_prints_the_state_or_refuses(self):
        base = ["resolve-state", "--env", "prod", "--region", "us-east-1"]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(cb.main(base + ["--trigger", "switch", "--confirm", "switch prod"]), 0)
            self.assertEqual(cb.main(base + ["--trigger", "drill", "--state", "replica"]), 2)
        self.assertEqual(out.getvalue().splitlines()[0], "replica")

    def test_the_failover_dispatch_resolves_to_replica(self):
        spec = importlib.util.spec_from_file_location("failover", Path(cb.__file__).with_name("failover.py"))
        fo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fo)
        body = {}
        ns = fo.parse_args(["--auto", "--cell", "cell-0", "--run-id", "hc-1", "--name-prefix", "pay", "--env", "prod", "--source-region", "eu-central-1",
                            "--target-region", "us-east-1", "--compute-build-url", "https://api.github.com/x/dispatches", "--compute-build-secret",
                            "arn:aws:secretsmanager:us-east-1:1:secret:t"])
        sw = fo.Switch(ns, client=lambda *a: Null(), http=lambda m, u, t, b=None: body.update(b or {}) or {})
        sw.token = "t"
        with contextlib.redirect_stdout(io.StringIO()):
            sw.start_compute_build()
        inputs = body["inputs"]
        self.assertEqual(cb.resolve_state(inputs["trigger"], "auto", inputs["confirm"], inputs["environment"]), "replica")


class Null:
    def __getattr__(self, name):
        return lambda **kw: {}


if __name__ == "__main__":
    unittest.main()
