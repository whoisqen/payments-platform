import json
import re
import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parents[1]
OBS = LIB.parent
sys.path.insert(0, str(LIB))
sys.path.insert(0, str(OBS / "coverage"))
import build  # noqa: E402
import coverage as cov  # noqa: E402

FILES = sorted((OBS / "dashboards").rglob("*.json"))
DOCS = {p: json.loads(p.read_text()) for p in FILES}
COUNTER = re.compile(r"(?:_total|_count|_sum|_bucket)$")
# postgres_exporter names this counter without the suffix
COUNTER_WITHOUT_SUFFIX = {"pg_stat_database_deadlocks"}
FORBIDDEN =("payment_id", "customer_id", "token", "pan", "card")


def panels(doc):
    return [p for p in doc["panels"] if p["type"] != "row"]


class DashboardStandardTest(unittest.TestCase):
    def test_all_levels_present(self):
        uids = {d["uid"] for d in DOCS.values()}
        wanted = {"platform-overview", "slo-overview", "payments", "router", "locker", "drainer", "scheduler", "cells", "data-stores", "backup", "dr-switch", "cost", "kubernetes", "edge"}
        self.assertEqual(wanted, uids)

    def test_committed_json_matches_generator(self):
        self.assertEqual(build.main(["--check"]), 0)

    def test_every_panel_has_title_unit_and_datasource(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                with self.subTest(dashboard=path.name, panel=p.get("title")):
                    self.assertTrue(p["title"])
                    self.assertTrue(p["fieldConfig"]["defaults"].get("unit"))
                    self.assertEqual(p["datasource"]["uid"], "${datasource}")

    def test_percent_panels_are_bounded(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                d = p["fieldConfig"]["defaults"]
                if d["unit"] == "percent":
                    with self.subTest(dashboard=path.name, panel=p["title"]):
                        self.assertIn("min", d)
                        self.assertIn("max", d)

    def test_grid_is_24_columns_without_overlap(self):
        for path, doc in DOCS.items():
            cells = {}
            for p in doc["panels"]:
                g = p["gridPos"]
                self.assertLessEqual(g["x"] + g["w"], 24, f"{path.name}: {p['title']}")
                for x in range(g["x"], g["x"] + g["w"]):
                    for y in range(g["y"], g["y"] + g["h"]):
                        self.assertNotIn((x, y), cells, f"{path.name}: {p['title']} overlaps {cells.get((x, y))}")
                        cells[(x, y)] = p["title"]

    def test_fixed_widths_by_type(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                w = p["gridPos"]["w"]
                with self.subTest(dashboard=path.name, panel=p["title"]):
                    if p["type"] in ("stat", "gauge"):
                        self.assertEqual(w, 4)
                    else:
                        self.assertIn(w, (12, 24))

    def test_at_most_25_panels(self):
        for path, doc in DOCS.items():
            self.assertLessEqual(len(panels(doc)), 25, path.name)

    def test_queries_use_variables_and_legends(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in p["targets"]:
                    with self.subTest(dashboard=path.name, panel=p["title"]):
                        self.assertIn("$env", t["expr"])
                        if p["type"] in ("timeseries", "barchart"):
                            self.assertTrue(t["legendFormat"], "legend must be a template, not raw labels")

    def test_rate_only_on_counters(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in p["targets"]:
                    for fn, metric in re.findall(r"\b(rate|increase)\(\s*([A-Za-z_:][A-Za-z0-9_:]*)", t["expr"]):
                        with self.subTest(dashboard=path.name, panel=p["title"], metric=metric):
                            if metric not in COUNTER_WITHOUT_SUFFIX:
                                self.assertRegex(metric, COUNTER)

    def test_latency_panels_use_quantiles_not_averages(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in p["targets"]:
                    if "duration" in t["expr"] or "latency" in t["expr"]:
                        self.assertNotRegex(t["expr"], r"\bavg(_over_time)?\(", f"{path.name}: {p['title']}")

    def test_standard_variables_and_defaults(self):
        for path, doc in DOCS.items():
            names = [v["name"] for v in doc["templating"]["list"]]
            self.assertEqual(names, ["datasource", "env", "region", "cell", "service", "psp"], path.name)
            by = {v["name"]: v for v in doc["templating"]["list"]}
            self.assertEqual(by["env"]["current"]["text"], "prod")
            self.assertEqual(by["region"]["current"]["text"], "eu-central-1")
            self.assertEqual(doc["time"]["from"], "now-6h")
            self.assertEqual(doc["refresh"], "30s")
            self.assertFalse(doc["editable"])

    def test_no_high_cardinality_labels(self):
        for path, doc in DOCS.items():
            text = json.dumps([t["expr"] + t["legendFormat"] for p in panels(doc) for t in p["targets"]])
            for word in FORBIDDEN:
                self.assertNotRegex(text, rf"\b{word}\b", f"{path.name} mentions {word}")

    def test_threshold_colors_follow_the_palette(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for step in p["fieldConfig"]["defaults"]["thresholds"]["steps"]:
                    self.assertIn(step["color"], ("green", "yellow", "red", "blue"), path.name)

    def test_links_point_to_existing_dashboards(self):
        uids = {d["uid"] for d in DOCS.values()}
        for path, doc in DOCS.items():
            for link in doc["links"]:
                self.assertIn(link["url"].split("/d/")[1], uids, path.name)

    def test_metrics_exist_in_catalog(self):
        catalog = set(json.loads((OBS / "coverage" / "metrics-catalog.json").read_text())["metrics"])
        _, recorded = cov.load_rules([OBS / "slo" / "generated"])
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in p["targets"]:
                    for m in cov.extract_metrics(t["expr"]):
                        with self.subTest(dashboard=path.name, metric=m):
                            self.assertTrue(m in catalog or m in recorded or m == "ALERTS", m)


if __name__ == "__main__":
    unittest.main()
