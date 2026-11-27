import sys
import unittest
from pathlib import Path

import yaml

CONFIG = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CONFIG))
sys.path.insert(0, str(CONFIG / "render"))
import clusters  # noqa: E402
import render_vault as rv  # noqa: E402

CFG = yaml.safe_load((rv.ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))


class RenderVaultTest(unittest.TestCase):
    def setUp(self):
        self.files = {k.relative_to(rv.ROOT / "deploy" / "platform").as_posix(): v for k, v in rv.render(CFG).items()}
        self.vault = yaml.safe_load(self.files["vault/envs/shared-services/eu-central-1.config.yaml"])

    def test_one_vault_in_shared_services_serves_every_environment(self):
        self.assertEqual([k for k in self.files if k.startswith("vault/")],
                         ["vault/envs/shared-services/eu-central-1.yaml", "vault/envs/shared-services/eu-central-1.config.yaml"])
        server = yaml.safe_load(self.files["vault/envs/shared-services/eu-central-1.yaml"])["server"]["extraEnvironmentVars"]
        self.assertEqual(server["VAULT_AWSKMS_SEAL_KEY_ID"], f"alias/{CFG['naming']['prefix']}-shared-services-euc1-vault-unseal")
        self.assertEqual(sorted(self.vault["bootstrap"]["workloads"]["environments"]), ["dev", "prod", "stage"])

    def test_only_prod_reads_vault_from_the_standby_region(self):
        envs = rv.environments(CFG)
        self.assertEqual(envs["dev"], ["eu-central-1"])
        self.assertEqual(envs["stage"], ["eu-central-1"])
        self.assertEqual(envs["prod"], ["eu-central-1", "us-east-1"])

    def test_every_cluster_of_the_live_tree_gets_a_mount_except_the_central_one(self):
        names = [c["name"] for c in self.vault["bootstrap"]["workloads"]["clusters"]]
        want = [c["name"] for c in clusters.clusters(CFG) if c["environment"] != "shared-services"]
        self.assertEqual(names, want)
        self.assertTrue(all(c["kind"] == "cell" for c in self.vault["bootstrap"]["workloads"]["clusters"] if c["component"] in clusters.CELLS))

    def test_external_secrets_reach_the_central_vault_through_the_internal_gateway(self):
        for env, regions in rv.environments(CFG).items():
            for region in regions:
                eso = yaml.safe_load(self.files[f"external-secrets/envs/{env}/{region}.yaml"])
                self.assertEqual(eso["vault"]["server"], f"https://{CFG['vault']['host']}:443")
                self.assertEqual(eso["networkPolicy"]["vaultCidrs"], [CFG["network"]["shared_services"]["eu-central-1"]])

    def test_no_placeholder_is_written(self):
        for text in self.files.values():
            self.assertNotIn("REPLACE_", text)
            self.assertNotIn("role-arn", text)


if __name__ == "__main__":
    unittest.main()
