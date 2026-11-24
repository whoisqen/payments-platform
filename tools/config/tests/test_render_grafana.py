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


class AccessTest(unittest.TestCase):
    """Who may log in to Grafana, with which role, and how a person is removed."""

    @classmethod
    def setUpClass(cls):
        cfg = yaml.safe_load((render_grafana.ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
        cls.groups = cfg["access"]["grafana_groups"]
        cls.ini = render_grafana.access(cls.groups)["grafana.ini"]
        cls.oauth = cls.ini["auth.generic_oauth"]

    def role_of(self, *member_of):
        """Evaluate the role expression for a person who is in the given groups (first match wins, like JMESPath ||)."""
        for part in self.oauth["role_attribute_path"].split(" || "):
            group, role = part.replace("contains(groups[*], '", "").replace("')", "").split(" && ")
            if group in member_of:
                return role.strip("'")
        return None

    def test_every_group_of_the_config_can_log_in_and_has_a_role(self):
        for key, group in self.groups.items():
            with self.subTest(group=group):
                self.assertIn(group, self.oauth["allowed_groups"].split(","))
                self.assertIsNotNone(self.role_of(group))

    def test_roles_follow_the_access_model(self):
        want = {"admin": "GrafanaAdmin", "sre": "Editor", "security": "Editor", "engineering": "Viewer", "finance": "Viewer", "audit": "Viewer"}
        for key, role in want.items():
            self.assertEqual(self.role_of(self.groups[key]), role, key)

    def test_the_strongest_role_wins_when_a_person_is_in_several_groups(self):
        self.assertEqual(self.role_of(self.groups["engineering"], self.groups["sre"]), "Editor")
        self.assertEqual(self.role_of(self.groups["audit"], self.groups["admin"]), "GrafanaAdmin")

    def test_a_person_in_no_group_has_no_access(self):
        self.assertIsNone(self.role_of("some-other-group"))
        self.assertTrue(self.oauth["role_attribute_strict"])

    def test_only_the_identity_provider_creates_users(self):
        self.assertTrue(self.ini["auth"]["disable_login_form"])
        self.assertFalse(self.ini["users"]["allow_sign_up"])
        self.assertTrue(self.oauth["allow_sign_up"])
        self.assertFalse(self.ini["auth"]["oauth_allow_insecure_email_lookup"])

    def test_the_role_is_checked_at_every_login_and_a_session_ends_within_a_day(self):
        self.assertFalse(self.oauth["skip_org_role_sync"])
        self.assertEqual(self.ini["auth"]["login_maximum_lifetime_duration"], "24h")
        self.assertLessEqual(int(self.ini["auth"]["login_maximum_inactive_lifetime_duration"].rstrip("h")), 8)

    def test_viewers_and_editors_cannot_change_dashboards_or_share_them_outside(self):
        self.assertFalse(self.ini["users"]["viewers_can_edit"])
        self.assertFalse(self.ini["users"]["editors_can_admin"])
        self.assertFalse(self.ini["snapshots"]["external_enabled"])
        self.assertFalse(self.ini["security"]["allow_embedding"])
        self.assertTrue(self.ini["security"]["cookie_secure"])

    def test_the_addon_loads_the_access_file_after_the_values(self):
        addon = (render_grafana.ROOT / "deploy" / "argocd" / "templates" / "addons" / "central" / "grafana.yaml").read_text(encoding="utf-8")
        self.assertLess(addon.index("grafana/values.yaml"), addon.index("grafana/access.yaml"))
