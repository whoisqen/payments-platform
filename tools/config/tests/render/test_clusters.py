import sys
import unittest
from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(CONFIG / "render"))
import clusters  # noqa: E402

ROOT = CONFIG.parents[1]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))


class ClustersTest(unittest.TestCase):
    def test_every_eks_unit_is_one_cluster(self):
        units = sorted(ROOT.glob("infra/live/*/*/*/eks/terragrunt.hcl"))
        got = clusters.clusters(CFG)
        self.assertEqual(len(got), len(units))
        self.assertEqual(len({c["name"] for c in got}), len(got))

    def test_names_match_the_argo_cd_names_of_the_eks_module(self):
        for c in clusters.clusters(CFG):
            short = clusters.SHORT[c["region"]]
            self.assertEqual(c["name"], f"{CFG['naming']['prefix']}-{c['environment']}-{short}-{c['component']}")

    def test_only_prod_has_clusters_in_the_standby_region_and_the_central_cluster_runs_vault(self):
        standby = {c["environment"] for c in clusters.clusters(CFG) if c["region"] == "us-east-1"}
        self.assertEqual(standby, {"prod"})
        central = [c for c in clusters.clusters(CFG) if c["component"] == "central"]
        self.assertEqual(len(central), 1)
        self.assertTrue(central[0]["inCluster"])
        self.assertEqual(central[0]["labels"]["payments-platform/vault"], "enabled")

    def test_argocd_values_register_every_cluster(self):
        sys.path.insert(0, str(CONFIG))
        import importlib.util
        spec = importlib.util.spec_from_file_location("argocd_values", CONFIG / "argocd-values.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        self.assertEqual(len(mod.values(CFG)["clusters"]), len(clusters.clusters(CFG)))


if __name__ == "__main__":
    unittest.main()
