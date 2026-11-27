import importlib.util
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location("argocd_values", ROOT / "tools" / "config" / "argocd-values.py")
argocd_values = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(argocd_values)
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
STANDBY = CFG["regions"]["recovery"][0]


class PilotLightTest(unittest.TestCase):
    def setUp(self):
        self.saved = argocd_values.sizing

    def tearDown(self):
        argocd_values.sizing = self.saved

    def test_every_pilot_light_region_matches_config(self):
        got = {(e["environment"], e["region"]) for e in argocd_values.values(CFG)["pilotLight"]}
        for f in (ROOT / "config" / "environments").glob("*.yaml"):
            s = argocd_values.sizing(f.stem)["standby"]
            expected = s["enabled"] and not s.get("compute_enabled", False)
            self.assertEqual((f.stem, STANDBY) in got, expected, f.stem)

    def test_switch_with_compute_enabled_clears_the_gate(self):
        argocd_values.sizing = lambda env: {"standby": {"enabled": True, "compute_enabled": True}}
        self.assertEqual(argocd_values.pilot_light(CFG), [])

    def test_environment_without_standby_is_not_gated(self):
        argocd_values.sizing = lambda env: {"standby": {"enabled": False}}
        self.assertEqual(argocd_values.pilot_light(CFG), [])

    def test_gated_region_has_a_directory_for_every_gated_environment(self):
        for e in argocd_values.values(CFG)["pilotLight"]:
            self.assertTrue((ROOT / "deploy" / "envs" / e["environment"] / e["region"]).is_dir(), e)


if __name__ == "__main__":
    unittest.main()
