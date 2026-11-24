import copy
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
        cls.orgs = cfg["access"]["grafana_orgs"]
        cls.ini = render_grafana.access(cls.groups, cls.orgs)["grafana.ini"]
        cls.oauth = cls.ini["auth.generic_oauth"]

    def role_of(self, *member_of):
        """Evaluate the role expression for a person who is in the given groups (first match wins, like JMESPath ||)."""
        for part in self.oauth["role_attribute_path"].split(" || "):
            group, role = part.replace("contains(groups[*], '", "").replace("')", "").split(" && ")
            if group in member_of:
                return role.strip("'")
        return None

    def test_the_role_expression_covers_the_main_organization_only(self):
        main = {self.groups[g] for g in self.orgs["main"]["groups"]}
        for key, group in self.groups.items():
            with self.subTest(group=group):
                self.assertEqual(self.role_of(group) is not None, group in main)

    def test_roles_follow_the_access_model(self):
        want = {"admin": "GrafanaAdmin", "sre": "Editor", "security": "Editor", "engineering": None, "finance": None, "audit": None}
        for key, role in want.items():
            self.assertEqual(self.role_of(self.groups[key]), role, key)

    def test_the_strongest_role_wins_when_a_person_is_in_several_groups(self):
        self.assertEqual(self.role_of(self.groups["engineering"], self.groups["sre"]), "Editor")
        self.assertEqual(self.role_of(self.groups["security"], self.groups["admin"]), "GrafanaAdmin")

    def test_a_person_in_no_group_has_no_access(self):
        self.assertIsNone(self.role_of("some-other-group"))
        self.assertTrue(self.oauth["role_attribute_strict"])
        # allowed_groups is the hard deny, independent of how the role is evaluated; only groups of a wired organization are in it
        self.assertNotIn("some-other-group", self.oauth["allowed_groups"].split(","))
        self.assertNotIn("some-other-group", self.oauth["org_mapping"])
        self.assertFalse(self.ini["users"]["auto_assign_org"])

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



def with_orgs(on):
    """The config with the non-main organizations switched on or off, and what it renders."""
    cfg = copy.deepcopy(CFG)
    cfg["access"]["grafana_bootstrap_image"] = {"repository": "registry.example.test/python", "digest": "sha256:" + "ab" * 32}
    for key, org in cfg["access"]["grafana_orgs"].items():
        if key != "main":
            org["provisioned"] = on
    return cfg, render_grafana.render(cfg)


class OrganizationsTest(unittest.TestCase):
    """Who sees which dashboards: the model is data in config/platform.yaml, independent of the switch `provisioned`."""

    @classmethod
    def setUpClass(cls):
        cls.groups = CFG["access"]["grafana_groups"]
        cls.orgs = CFG["access"]["grafana_orgs"]
        cls.catalog = render_grafana.catalog()
        cls.all = {f"{folder}/{name}" for folder, files in cls.catalog.items() for name in files}
        cls.on_cfg, cls.on = with_orgs(True)
        cls.off_cfg, cls.off = with_orgs(False)

    def seen(self, key):
        return {f"{folder}/{name}" for folder, names in render_grafana.visible(self.orgs[key], self.catalog).items() for name in names}

    def test_the_model_is_consistent(self):
        render_grafana.check_orgs(self.groups, self.orgs, self.catalog, self.on_cfg["access"]["grafana_bootstrap_image"])

    def test_every_dashboard_is_visible_to_the_main_organization(self):
        self.assertEqual(self.seen("main"), self.all)

    def test_every_dashboard_is_visible_to_someone(self):
        self.assertEqual(set().union(*(self.seen(k) for k in self.orgs)), self.all)

    def test_finance_never_sees_a_dashboard_outside_finops(self):
        self.assertEqual({d.split("/")[0] for d in self.seen("finance")}, {"finops"})
        for path in self.on:
            if path.name.startswith("org-finance-"):
                self.assertEqual(path.name, "org-finance-finops.yaml")
        self.assertEqual(set(load_in(self.on, "org-finance-finops.yaml")["data"]), {"cost.json"})

    def test_engineering_sees_l0_l1_l2_and_audit_the_compliance_set(self):
        self.assertEqual({d.split("/")[0] for d in self.seen("engineering")}, {"l0-overview", "l1-services", "l2-platform"})
        self.assertEqual(self.seen("audit"), {"l0-overview/platform-overview.json", "l0-overview/slo-overview.json",
                                              "l3-data/backup.json", "l3-edge/edge.json", "l3-data/dr-switch.json"})

    def test_the_cde_locker_dashboard_stays_out_of_the_finance_and_audit_organizations(self):
        for key in ("finance", "audit"):
            self.assertNotIn("l1-services/locker.json", self.seen(key))

    def test_an_unknown_dashboard_group_or_a_group_without_organization_is_refused(self):
        for mutate in (lambda o: o["audit"]["dashboards"]["uids"].append("nope"),
                       lambda o: o["audit"]["groups"].update({"ghost": "Viewer"}),
                       lambda o: o["finance"]["groups"].clear(),
                       lambda o: o["finance"]["groups"].update({"finance": "GrafanaAdmin"})):
            orgs = copy.deepcopy(self.orgs)
            mutate(orgs)
            with self.assertRaises(ValueError):
                render_grafana.check_orgs(self.groups, orgs, self.catalog, self.on_cfg["access"]["grafana_bootstrap_image"])

    def test_org_mapping_uses_ids_and_org_roles_only(self):
        ini = load_in(self.on, "access.yaml")["grafana.ini"]["auth.generic_oauth"]
        mapping = dict((e.split(":")[0], tuple(e.split(":")[1:])) for e in ini["org_mapping"].split(","))
        want = {self.groups["admin"]: ("1", "Admin"), self.groups["sre"]: ("1", "Editor"), self.groups["security"]: ("1", "Editor"),
                self.groups["engineering"]: ("2", "Viewer"), self.groups["finance"]: ("3", "Viewer"), self.groups["audit"]: ("4", "Viewer")}
        self.assertEqual(mapping, want)
        self.assertEqual(set(ini["allowed_groups"].split(",")), set(self.groups.values()))

    def test_an_organization_that_is_not_provisioned_is_created_but_wired_to_nothing(self):
        values = load_in(self.off, "access.yaml")
        for key in ("dashboardProviders", "dashboardsConfigMaps", "datasources"):
            self.assertNotIn(key, values)
        ini = values["grafana.ini"]["auth.generic_oauth"]
        for key in ("engineering", "finance", "audit"):
            self.assertNotIn(self.groups[key], ini["allowed_groups"].split(","))
            self.assertNotIn(self.groups[key], ini["org_mapping"])
        self.assertFalse([p for p in self.off if p.name.startswith("org-") and p.name != "org-bootstrap.yaml"])
        orgs = json.loads(load_in(self.off, "org-bootstrap.yaml", all_docs=True)[0]["data"]["orgs.json"])["orgs"]
        self.assertEqual([o["id"] for o in orgs], [1, 2, 3, 4])

    def test_providers_use_the_organization_id_and_the_config_maps_carry_no_sidecar_label(self):
        values = load_in(self.on, "access.yaml")
        providers = values["dashboardProviders"]["org-providers.yaml"]["providers"]
        ids = {k: o["id"] for k, o in self.orgs.items()}
        for provider in providers:
            org = provider["name"].split("-")[1]
            self.assertEqual(provider["orgId"], ids[org])
            self.assertTrue(provider["options"]["path"].endswith(provider["name"]))
            self.assertEqual(values["dashboardsConfigMaps"][provider["name"]], f"grafana-{provider['name']}")
        for path, text in self.on.items():
            if path.name.startswith("org-") and path.name != "org-bootstrap.yaml":
                self.assertNotIn("grafana_dashboard", yaml.safe_load(text)["metadata"].get("labels", {}))

    def test_every_organization_has_the_data_source_its_dashboards_use(self):
        sources = load_in(self.on, "access.yaml")["datasources"]["datasources-orgs.yaml"]["datasources"]
        for key, org in self.orgs.items():
            if key == "main":
                continue
            mine = [d for d in sources if d["orgId"] == org["id"]]
            self.assertEqual(sum(bool(d.get("isDefault")) for d in mine), 1, key)
            self.assertEqual({d["uid"] for d in mine}, set(org["datasources"]))
            types = {d["type"] for d in mine}
            for folder, names in render_grafana.visible(org, self.catalog).items():
                for name in names:
                    self.assertLessEqual(datasource_types(render_grafana.DASHBOARDS / folder / name), types, f"{key} {folder}/{name}")

    def test_the_placeholder_image_renders_no_job_and_blocks_provisioning(self):
        cfg = copy.deepcopy(CFG)
        self.assertFalse([p for p in render_grafana.render(cfg) if p.name == "org-bootstrap.yaml"])
        for org in cfg["access"]["grafana_orgs"].values():
            org["provisioned"] = True
        with self.assertRaises(ValueError):
            render_grafana.render(cfg)

    def test_the_bootstrap_job_is_a_postsync_hook_with_the_secret_by_reference(self):
        cm, job = load_in(self.off, "org-bootstrap.yaml", all_docs=True)
        self.assertEqual(job["metadata"]["annotations"]["argocd.argoproj.io/hook"], "PostSync")
        container = job["spec"]["template"]["spec"]["containers"][0]
        self.assertRegex(container["image"], r"@sha256:[0-9a-f]{64}$")
        for env in container["env"]:
            if env["name"].startswith("GRAFANA_ADMIN"):
                self.assertEqual(env["valueFrom"]["secretKeyRef"]["name"], "grafana-admin")
                self.assertNotIn("value", env)
        self.assertEqual(cm["data"]["bootstrap_orgs.py"], render_grafana.BOOTSTRAP_SCRIPT.read_text(encoding="utf-8"))
        self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])


def load_in(files, name, all_docs=False):
    for path, text in files.items():
        if path.name == name:
            docs = list(yaml.safe_load_all(text))
            return docs if all_docs else docs[0]
    raise KeyError(name)


def datasource_types(path):
    found = set()

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("datasource"), dict) and node["datasource"].get("type"):
                found.add(node["datasource"]["type"])
            if node.get("type") == "datasource" and node.get("query"):
                found.add(node["query"])
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(json.loads(path.read_text(encoding="utf-8")))
    return found
