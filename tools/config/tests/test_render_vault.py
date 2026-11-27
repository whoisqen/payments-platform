import sys
import unittest
from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CONFIG))
import render_vault as rv  # noqa: E402

CFG = {
    "naming": {"prefix": "acme"},
    "registry": {"ecr_prefix": "1.dkr.ecr.eu-central-1.amazonaws.com", "ecr_repo_prefix": "pay"},
    "accounts": {"dev": "111111111111", "stage": "333333333333"},
    "regions": {"working": "eu-central-1", "recovery": ["us-east-1"]},
    "network": {"dev": {"eu-central-1": "10.1.0.0/16"},
                "stage": {"eu-central-1": "10.2.0.0/16", "us-east-1": "10.3.0.0/16"}},
    "dns": {"dev_zone": "dev.example.com", "stage_zone": "stage.example.com"},
    "deploy": {"dev": {"endpoint_cidrs": ["10.1.255.0/24"]},
               "stage": {"endpoint_cidrs": ["10.2.255.0/24"],
                         "standby": {"us-east-1": {"endpoint_cidrs": ["10.3.0.0/18"]}}}},
}


class RenderVaultTest(unittest.TestCase):
    def setUp(self):
        self.files = {k.relative_to(rv.ROOT / "deploy" / "platform").as_posix(): v for k, v in rv.render(CFG).items()}

    def test_regions_per_environment(self):
        self.assertEqual(rv.environments(CFG), {"dev": ["eu-central-1"], "stage": ["eu-central-1", "us-east-1"]})
        self.assertEqual(len(self.files), 9)

    def test_names_follow_the_contract(self):
        server = yaml.safe_load(self.files["vault/envs/stage/us-east-1.yaml"])["server"]["extraEnvironmentVars"]
        self.assertEqual(server["VAULT_AWSKMS_SEAL_KEY_ID"], "alias/acme-stage-use1-vault-unseal")
        cfg = yaml.safe_load(self.files["vault/envs/stage/us-east-1.config.yaml"])
        self.assertEqual(cfg["snapshot"]["bucket"], "acme-stage-use1-vault-snapshots")
        self.assertEqual(cfg["snapshot"]["image"]["repository"], "1.dkr.ecr.eu-central-1.amazonaws.com/pay/vault-snapshot")
        self.assertEqual(cfg["bootstrap"]["initSecretId"], "acme/stage/vault/init")
        self.assertEqual(cfg["networkPolicy"]["awsEndpointCidrs"], ["10.3.0.0/18"])
        eso = yaml.safe_load(self.files["external-secrets/envs/stage/eu-central-1.yaml"])
        self.assertEqual(eso["vault"]["server"], "https://vault.stage.example.com:8200")

    def test_vault_roles_follow_the_cells_of_each_environment(self):
        for env, regions in rv.environments(CFG).items():
            work = rv.ROOT / "deploy" / "envs" / env / CFG["regions"]["working"]
            expected = sorted(d.name for d in work.iterdir() if d.name.startswith("cell-") or d.name == "spare")
            for region in regions:
                got = yaml.safe_load(self.files[f"vault/envs/{env}/{region}.config.yaml"])["bootstrap"]["workloads"]["cells"]
                self.assertEqual([c["name"] for c in got], expected)
                self.assertEqual(got[0], {"name": "cell-0", "authMount": "kubernetes"})

    def test_no_placeholder_is_written(self):
        for text in self.files.values():
            self.assertNotIn("REPLACE_", text)
            self.assertNotIn("role-arn", text)


if __name__ == "__main__":
    unittest.main()
