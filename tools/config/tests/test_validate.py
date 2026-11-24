import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import validate  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
ENVS = ROOT / "config" / "environments"


def load(name):
    return yaml.safe_load((ENVS / f"{name}.yaml").read_text(encoding="utf-8"))


class SizingTest(unittest.TestCase):
    def test_committed_files_are_valid(self):
        for env in ("dev", "stage", "prod"):
            self.assertEqual(validate.check_sizing(load("prod"), load(env), env), [])

    def test_stage_repeats_prod_except_the_capacity_type(self):
        stage = load("stage")
        self.assertEqual(set(stage), {"eks"})
        self.assertEqual(set(stage["eks"]), {"spot_pools"})

    def test_production_uses_no_spot_and_has_a_standby(self):
        prod = load("prod")
        self.assertEqual(prod["eks"]["spot_pools"], [])
        self.assertTrue(prod["standby"]["enabled"])

    def test_cde_pool_can_never_be_spot(self):
        own = {"eks": {"spot_pools": ["cde"]}}
        self.assertTrue(any("never Spot" in e for e in validate.check_sizing(load("prod"), own, "x")))

    def test_an_override_may_not_invent_keys_or_sections(self):
        errors = validate.check_sizing(load("prod"), {"aurora": {"writer": "db.r7g.large"}, "kafka": {}}, "x")
        self.assertEqual(len(errors), 2)

    def test_bad_instance_class_is_rejected(self):
        errors = validate.check_sizing(load("prod"), {"aurora": {"writer_class": "large"}}, "x")
        self.assertTrue(any("writer_class" in e for e in errors))

    def test_a_warm_standby_needs_a_reader(self):
        errors = validate.check_sizing(load("prod"), {"standby": {"reader_count": 0}}, "x")
        self.assertTrue(any("reader_count" in e for e in errors))

    def test_dev_has_no_standby_and_no_readers(self):
        dev = load("dev")
        self.assertFalse(dev["standby"]["enabled"])
        self.assertEqual(dev["aurora"]["reader_count"], 0)


class GrafanaGroupsTest(unittest.TestCase):
    def cfg(self):
        return yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))

    def test_every_role_needs_a_group(self):
        cfg = self.cfg()
        del cfg["access"]["grafana_groups"]["audit"]
        self.assertTrue(any("grafana_groups.audit" in e for e in validate.check(cfg)))

    def test_two_roles_cannot_share_a_group(self):
        cfg = self.cfg()
        cfg["access"]["grafana_groups"]["audit"] = cfg["access"]["grafana_groups"]["admin"]
        self.assertTrue(any("different group" in e for e in validate.check(cfg)))


class ConfigTest(unittest.TestCase):
    def test_platform_config_is_valid_and_has_prod(self):
        cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
        self.assertEqual(validate.check(cfg), [])
        self.assertIn("prod", cfg["accounts"])
        self.assertIn("prod", cfg["network"])


if __name__ == "__main__":
    unittest.main()
