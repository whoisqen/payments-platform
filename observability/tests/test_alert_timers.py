"""Anti-flap timers of every alert and the rule that a firing alert is announced once.

Kinds of alert rule:
  event      `increase(x[W]) > 0`: the window keeps it firing for W after the last event, so it needs no timers, but W must be long enough;
  burn rate  generated multi-window SLO alerts: the windows are the pending period, a hold time stops flapping at the threshold;
  threshold  everything else: `for` ignores a blip, `keep_firing_for` stops a rate hovering around the limit from firing and resolving again.
"""
import re
import unittest
from pathlib import Path

import yaml

OBS = Path(__file__).resolve().parents[1]
UNIT = {"s": 1 / 60, "m": 1, "h": 60, "d": 1440}
MIN_FOR = {"critical": 2, "warning": 5}
MIN_KEEP = {"critical": 5, "warning": 10}
MIN_BURN_KEEP = {"critical": 10, "warning": 30}
MIN_EVENT_WINDOW = 10
NEVER_REPEAT_HOURS = 8760
DETECTION_OVERHEAD = 3


def minutes(text):
    match = re.fullmatch(r"(\d+)([smhd])", str(text))
    return int(match.group(1)) * UNIT[match.group(2)] if match else None


def hours(text):
    return minutes(text) / 60


def rules():
    found = []
    for path in sorted((OBS / "alerts").rglob("*.yaml")) + sorted((OBS / "slo" / "generated").glob("*.yaml")):
        for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")):
            if isinstance(doc, dict) and doc.get("kind") == "PrometheusRule":
                for group in doc["spec"]["groups"]:
                    found += [r for r in group["rules"] if "alert" in r]
    return found


def kind(rule):
    expr = re.sub(r"\s+", " ", rule["expr"])
    if rule["alert"] == "Watchdog":
        return "meta"
    if expr.startswith("slo:sli_error:ratio_rate"):
        return "burn"
    if re.search(r"increase\(.*\)\s*>\s*0\s*$", expr):
        return "event"
    return "threshold"


RULES = rules()
CONFIG = yaml.safe_load((OBS / "alertmanager" / "alertmanager.yaml").read_text(encoding="utf-8"))


def of_kind(name):
    return [r for r in RULES if kind(r) == name and r["labels"].get("severity") in MIN_FOR]


class TimerPolicy(unittest.TestCase):
    def test_every_kind_is_recognised(self):
        self.assertGreater(len(of_kind("threshold")), 50)
        self.assertGreater(len(of_kind("burn")), 5)
        self.assertGreater(len(of_kind("event")), 5)

    def test_threshold_alerts_wait_before_firing(self):
        for rule in of_kind("threshold"):
            sev = rule["labels"]["severity"]
            with self.subTest(alert=rule["alert"]):
                self.assertIn("for", rule, "a blip must not fire an alert")
                self.assertGreaterEqual(minutes(rule["for"]), MIN_FOR[sev], f"{sev} needs for >= {MIN_FOR[sev]}m")

    def test_threshold_alerts_keep_firing_after_the_condition_clears(self):
        for rule in of_kind("threshold"):
            sev = rule["labels"]["severity"]
            with self.subTest(alert=rule["alert"]):
                self.assertIn("keep_firing_for", rule, "without it the alert fires and resolves again around the limit")
                self.assertGreaterEqual(minutes(rule["keep_firing_for"]), MIN_KEEP[sev])

    def test_burn_rate_alerts_hold_after_their_windows_clear(self):
        for rule in of_kind("burn"):
            with self.subTest(alert=rule["alert"]):
                self.assertGreaterEqual(minutes(rule.get("keep_firing_for", "0m")), MIN_BURN_KEEP[rule["labels"]["severity"]])

    def test_event_alerts_stay_firing_long_enough_to_latch(self):
        # the lookback window plus the hold after it: a second event in that time is the same alert, not a new one
        for rule in of_kind("event"):
            window = re.search(r"increase\([^)]*\[(\d+[smhd])\]", re.sub(r"\s+", " ", rule["expr"]))
            with self.subTest(alert=rule["alert"]):
                self.assertIsNotNone(window)
                held = minutes(window.group(1)) + minutes(rule.get("keep_firing_for", "0m"))
                self.assertGreaterEqual(held, MIN_EVENT_WINDOW)

    def test_catalog_detection_time_covers_the_pending_period(self):
        # scrape, evaluation and group_wait need about 3 minutes on top of `for`
        modes = {m["alert"]: m for p in sorted((OBS / "coverage" / "catalog").glob("*.yaml")) for m in yaml.safe_load(p.read_text(encoding="utf-8"))["modes"] if m.get("alert")}
        for rule in RULES:
            if rule["alert"] in modes:
                with self.subTest(alert=rule["alert"]):
                    self.assertGreaterEqual(minutes(modes[rule["alert"]]["detect_within"]), minutes(rule.get("for", "0m")) + DETECTION_OVERHEAD)

    def test_a_pending_period_is_never_longer_than_the_hold(self):
        for rule in RULES:
            if "for" in rule and "keep_firing_for" in rule:
                with self.subTest(alert=rule["alert"]):
                    self.assertLessEqual(minutes(rule["keep_firing_for"]), 24 * 60)


class NoRepeat(unittest.TestCase):
    def walk(self, route, inherited):
        interval = route.get("repeat_interval", inherited)
        yield route, interval
        for child in route.get("routes", []):
            yield from self.walk(child, interval)

    def test_a_firing_alert_is_not_sent_again(self):
        for route, interval in self.walk(CONFIG["route"], None):
            matchers = " ".join(route.get("matchers", []))
            if "Watchdog" in matchers:
                continue
            with self.subTest(receiver=route["receiver"], matchers=matchers):
                self.assertIsNotNone(interval)
                self.assertGreaterEqual(hours(interval), NEVER_REPEAT_HOURS)

    def test_only_the_dead_mans_switch_repeats(self):
        repeating = [r for r, i in self.walk(CONFIG["route"], None) if hours(i or "8760h") < NEVER_REPEAT_HOURS]
        self.assertEqual([r["receiver"] for r in repeating], ["deadmans-switch"])
        self.assertEqual([m for r in repeating for m in r["matchers"]], ['alertname="Watchdog"'])

    def test_resolution_is_announced_once(self):
        for receiver in CONFIG["receivers"]:
            for slack in receiver.get("slack_configs", []):
                with self.subTest(receiver=receiver["name"]):
                    self.assertTrue(slack["send_resolved"])


if __name__ == "__main__":
    unittest.main()
