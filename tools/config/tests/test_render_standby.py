import copy
import re
import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_standby

ROOT = Path(__file__).resolve().parents[3]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
PREFIX = CFG["storage"]["state_bucket_prefix"]
WORK, STANDBY = CFG["regions"]["working"], CFG["regions"]["recovery"][0]
WS, SS = render_standby.short(WORK), render_standby.short(STANDBY)
OUT = {env: render_standby.render(CFG, env) for env in render_standby.ENVS}


def load(path):
    return yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}


def merge(a, b):
    out = copy.deepcopy(a)
    for k, v in b.items():
        out[k] = merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else copy.deepcopy(v)
    return out


def paths(d, pre=""):
    for k, v in d.items():
        p = f"{pre}.{k}" if pre else k
        if isinstance(v, dict):
            yield from paths(v, p)
        else:
            yield p


def cells(env):
    base = ROOT / "deploy" / "envs" / env / WORK
    return sorted(p.name for p in base.iterdir() if p.name.startswith("cell-") or p.name == "spare")


def standby_cell(env, cell):
    return yaml.safe_load(OUT[env][ROOT / "deploy" / "envs" / env / STANDBY / cell / "values.yaml"])


def layered(env, region, cell):
    base = ROOT / "deploy" / "envs" / env
    layers = [base / "values.yaml", base / region / "values.yaml"]
    top = standby_cell(env, cell) if region == STANDBY else load(base / region / cell / "values.yaml")
    out = {}
    for layer in [load(p) for p in layers] + [top]:
        out = merge(out, layer)
    return out


class RenderStandbyTest(unittest.TestCase):
    def each(self):
        for env in render_standby.ENVS:
            self.assertTrue(cells(env), env)
            for cell in cells(env):
                with self.subTest(env=env, cell=cell):
                    yield env, cell, standby_cell(env, cell)

    def test_every_working_cell_has_a_standby_layer(self):
        for env in render_standby.ENVS:
            rendered = {p.parent.name for p in OUT[env] if p.parent.parent.name == STANDBY}
            self.assertLessEqual(set(cells(env)), rendered)

    def test_hyperswitch_points_at_the_standby_proxy_memorydb_and_kms(self):
        for env, cell, v in self.each():
            hs = v["global"]["hyperswitch"]
            rds, mdb = CFG["deploy"][env]["rds_suffix"], CFG["deploy"][env]["memorydb_suffix"]
            self.assertEqual(hs["database"]["host"],
                             f"{PREFIX}-{env}-{SS}-aurora-{cell}.proxy-{rds}.{STANDBY}.rds.amazonaws.com")
            # The proxy has no read-only endpoint and PGSSLROOTCERT trusts only the proxy certificate: no direct reader
            self.assertNotIn("readerHost", hs["database"])
            self.assertEqual(hs["redis"]["host"],
                             f"clustercfg.{PREFIX}-{env}-{SS}-memorydb-{cell}.{mdb}.memorydb.{STANDBY}.amazonaws.com")
            self.assertEqual(hs["kms"], {"keyAlias": f"alias/{PREFIX}-{env}-{SS}-{cell}", "region": STANDBY})
            self.assertEqual(v["global"]["cell"], cell)

    def test_no_placeholder_or_working_region_endpoint(self):
        for env, cell, v in self.each():
            text = yaml.safe_dump(v)
            self.assertNotIn(".invalid", text)
            self.assertNotIn(WORK, text)
            self.assertNotRegex(text, rf"-{WS}-")

    def test_no_per_service_host_overrides(self):
        # An explicit host in container.env wins over global.hyperswitch in platform-common, so none may remain
        for env, cell, v in self.each():
            for p in paths(v):
                self.assertIsNone(re.search(r"container\.env\..*__(DATABASE|REDIS)__HOST$", p), p)

    def test_migrations_stay_disabled_on_the_secondary_writer_endpoint(self):
        for env, cell, v in self.each():
            self.assertIs(v["migrations"]["enabled"], False)
            self.assertEqual(v["migrations"]["database"]["host"],
                             f"{PREFIX}-{env}-{SS}-aurora-{cell}.cluster-{CFG['deploy'][env]['rds_suffix']}.{STANDBY}.rds.amazonaws.com")

    def test_shape_mirrors_the_working_region_layer(self):
        extra = {"migrations.enabled", "global.hyperswitch.kms.keyAlias", "global.hyperswitch.kms.region"}
        for env, cell, v in self.each():
            work = load(ROOT / "deploy" / "envs" / env / WORK / cell / "values.yaml")
            self.assertEqual(set(paths(v)), set(paths(work)) | extra)

    def test_merged_hyperswitch_settings_match_the_working_region(self):
        # Tenant, config file, users and locker come from the shared environment layer; only endpoints and the key differ
        endpoints = {"database", "redis", "kms"}
        for env, cell, _ in self.each():
            s = layered(env, STANDBY, cell)["global"]["hyperswitch"]
            w = layered(env, WORK, cell)["global"]["hyperswitch"]
            self.assertTrue(s.get("tenant", {}).get("baseUrl"), "tenant.baseUrl must come from the environment layer")
            self.assertEqual({k: x for k, x in s.items() if k not in endpoints},
                             {k: x for k, x in w.items() if k not in endpoints})
            self.assertEqual(layered(env, STANDBY, cell)["global"]["region"], STANDBY)

    def test_check_reports_no_drift(self):
        self.assertEqual(render_standby.main(["--check"]), 0)


if __name__ == "__main__":
    unittest.main()
