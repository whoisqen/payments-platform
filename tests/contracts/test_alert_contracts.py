import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "observability" / "coverage"))

import alert_coverage as ac  # noqa: E402

ALERTS, RECORDED = ac.load_rules([ac.OBS / "alerts", ac.OBS / "slo" / "generated"])
MODES = ac.load_catalog(ac.HERE / "catalog")
MODE_BY_ID = {m["id"]: m for m in MODES}


def slug(heading):
    return re.sub(r"[^a-z0-9 _-]", "", heading.lower()).replace(" ", "-")


def anchors(path):
    return {slug(ln.lstrip("#").strip()) for ln in path.read_text(encoding="utf-8").splitlines() if ln.startswith("#")}


class AlertLabels(unittest.TestCase):
    def test_rules_are_loaded(self):
        self.assertGreaterEqual(len(ALERTS), 50)
        self.assertEqual(len(MODE_BY_ID), len(MODES), "failure mode ids are unique")

    def test_every_alert_has_a_known_failure_mode(self):
        for name, rule in ALERTS.items():
            with self.subTest(alert=name):
                self.assertIn(rule.get("labels", {}).get("failure_mode"), MODE_BY_ID)

    def test_failure_mode_label_agrees_with_the_catalog_layer(self):
        for name, rule in ALERTS.items():
            mode = MODE_BY_ID.get(rule["labels"].get("failure_mode"))
            with self.subTest(alert=name):
                self.assertEqual(mode["layer"], rule["labels"]["layer"])
                self.assertIn(mode.get("alert"), ALERTS)

    def test_catalog_alerts_exist_in_rules_with_the_same_failure_mode(self):
        for mode in MODES:
            if mode.get("alert"):
                with self.subTest(mode=mode["id"]):
                    self.assertIn(mode["alert"], ALERTS)
                    self.assertEqual(ALERTS[mode["alert"]]["labels"]["failure_mode"], mode["id"])

    def test_required_labels_and_annotations_are_present(self):
        for name, rule in ALERTS.items():
            with self.subTest(alert=name):
                for key in ac.REQUIRED_LABELS:
                    self.assertTrue(rule["labels"].get(key), key)
                for key in ac.REQUIRED_ANNOTATIONS:
                    self.assertTrue(rule["annotations"].get(key), key)


class RunbookLinks(unittest.TestCase):
    def test_runbook_url_points_to_an_existing_runbook(self):
        for name, rule in ALERTS.items():
            url = rule["annotations"]["runbook_url"]
            with self.subTest(alert=name):
                path = ac.runbook_path(url)
                self.assertIsNotNone(path, url)
                self.assertTrue(path.is_file(), url)

    def test_runbook_anchor_resolves_to_a_heading(self):
        for name, rule in ALERTS.items():
            url = rule["annotations"]["runbook_url"]
            if "#" not in url:
                continue
            with self.subTest(alert=name):
                self.assertIn(url.split("#", 1)[1], anchors(ac.runbook_path(url)))

    def test_runbook_has_a_diagnostics_section(self):
        for name, rule in ALERTS.items():
            path = ac.runbook_path(rule["annotations"]["runbook_url"])
            with self.subTest(alert=name):
                self.assertRegex(path.read_text(encoding="utf-8"), ac.DIAGNOSTICS_HEADING)

    def test_runbook_layer_directory_matches_the_alert_layer(self):
        for name, rule in ALERTS.items():
            path = ac.runbook_path(rule["annotations"]["runbook_url"])
            with self.subTest(alert=name):
                self.assertIn(path.parent.name, {rule["labels"]["layer"], "slo"})

    def test_every_runbook_file_is_referenced_by_some_alert_or_is_meta(self):
        used = {ac.runbook_path(r["annotations"]["runbook_url"]) for r in ALERTS.values()}
        for f in sorted((ROOT / "docs" / "runbooks").rglob("*.md")):
            if f.name != "README.md":
                with self.subTest(runbook=str(f.relative_to(ROOT))):
                    self.assertTrue(f in used or f.parent.name == "meta", "orphan runbook")


class Validators(unittest.TestCase):
    def test_check_mode_flags_a_missing_runbook(self):
        rule = {"expr": "up", "labels": {k: "x" for k in ac.REQUIRED_LABELS},
                "annotations": {"summary": "s", "dashboard_url": "d", "runbook_url": "https://h/docs/runbooks/none/missing.md"}}
        got = ac.check_mode({"alert": "A"}, {"A": rule}, set(), {"up"})
        self.assertEqual(got, "runbook file does not exist")

    def test_check_mode_flags_a_missing_label(self):
        rule = {"expr": "up", "labels": {"severity": "x"}, "annotations": {}}
        self.assertIn("lacks", ac.check_mode({"alert": "A"}, {"A": rule}, set(), {"up"}))


if __name__ == "__main__":
    unittest.main()
