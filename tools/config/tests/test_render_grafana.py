import json
import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_grafana  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = render_grafana.render(CFG)
PLATFORM = render_grafana.OUT


def load(path):
    return yaml.safe_load(OUT[path])


class RenderGrafanaTest(unittest.TestCase):
    def test_committed_files_are_current(self):
        for path, text in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), text, f"run tools/config/render_grafana.py: {path}")

    def test_region_short_code(self):
        self.assertEqual(render_grafana.region_short("eu-central-1"), "euc1")
        self.assertEqual(render_grafana.region_short("us-east-2"), "use2")

    def test_buckets_follow_the_naming_contract(self):
        prefix, region = CFG["naming"]["prefix"], CFG["regions"]["working"]
        short = render_grafana.region_short(region)
        loki = load(PLATFORM / "loki" / "storage.yaml")["loki"]["storage"]
        self.assertEqual(set(loki["bucketNames"].values()), {f"{prefix}-shared-services-{short}-loki"})
        self.assertEqual(loki["s3"]["region"], region)
        tempo = load(PLATFORM / "tempo" / "storage.yaml")["storage"]["trace"]["s3"]
        self.assertEqual(tempo["bucket"], f"{prefix}-shared-services-{short}-tempo")

    def test_every_dashboard_is_provisioned_in_a_folder(self):
        sources = {p.name for p in render_grafana.DASHBOARDS.glob("*/*.json")}
        provisioned = set()
        for path in OUT:
            if path.name.startswith("dashboards-"):
                cm = load(path)
                self.assertIn("grafana_folder", cm["metadata"]["annotations"])
                self.assertEqual(cm["metadata"]["labels"]["grafana_dashboard"], "1")
                self.assertLess(sum(len(v) for v in cm["data"].values()), 900_000)
                for name, text in cm["data"].items():
                    json.loads(text)
                    provisioned.add(name)
        self.assertEqual(provisioned, sources)

    def test_folder_titles(self):
        self.assertEqual(render_grafana.folder_title("l0-overview"), "L0 Overview")
        self.assertEqual(render_grafana.folder_title("finops"), "FinOps")

    def test_secrets_come_from_the_contract_names(self):
        prefix = CFG["naming"]["prefix"]
        manifests = PLATFORM / "grafana" / "manifests"
        for file, secret in (("externalsecret-admin.yaml", "admin"), ("externalsecret-oidc.yaml", "oidc")):
            es = load(manifests / file)
            self.assertEqual(es["spec"]["secretStoreRef"]["name"], "aws-secrets-manager")
            for item in es["spec"]["data"]:
                self.assertEqual(item["remoteRef"]["key"], f"{prefix}/shared-services/grafana/{secret}")

    def test_sizing_of_the_stores(self):
        loki = yaml.safe_load((PLATFORM / "loki" / "values.yaml").read_text(encoding="utf-8"))
        self.assertEqual(loki["loki"]["limits_config"]["retention_period"], "720h")
        self.assertEqual((loki["write"]["replicas"], loki["read"]["replicas"], loki["backend"]["replicas"]), (3, 3, 3))
        tempo = yaml.safe_load((PLATFORM / "tempo" / "values.yaml").read_text(encoding="utf-8"))
        self.assertEqual(tempo["compactor"]["config"]["compaction"]["block_retention"], "336h")
        self.assertTrue(tempo["traces"]["otlp"]["grpc"]["enabled"])
        self.assertEqual(yaml.safe_load((PLATFORM / "grafana" / "values.yaml").read_text(encoding="utf-8"))["replicas"], 2)


if __name__ == "__main__":
    unittest.main()
