import json
import math
import re
import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parents[1]
OBS = LIB.parent
sys.path.insert(0, str(LIB))
sys.path.insert(0, str(OBS / "coverage"))
import build  # noqa: E402
import thresholds  # noqa: E402
from panels import LEVEL_TIME  # noqa: E402
import alert_coverage as cov  # noqa: E402
import yaml  # noqa: E402

LEVEL = {"l0-overview": "l0", "l1-services": "l1", "l2-platform": "l2", "l3-data": "l3", "l3-edge": "l3", "finops": "finops"}
STAT_KINDS = ("stat", "gauge")
# Group-by labels with more than a handful of values; such panels must cap their series.
WIDE_LABELS = re.compile(r"by \((?:[a-z_]+, )*(pod|node|instance|namespace|horizontalpodautoscaler|consumergroup|table_name|bucket|target|queue|store)\b")

FILES = sorted((OBS / "dashboards").rglob("*.json"))
DOCS = {p: json.loads(p.read_text()) for p in FILES}
COUNTER = re.compile(r"(?:_total|_count|_sum|_bucket)$")
# postgres_exporter and logstash-exporter name these counters without the suffix
COUNTER_WITHOUT_SUFFIX = {"pg_stat_database_deadlocks", "logstash_stats_pipeline_events_in", "logstash_stats_pipeline_events_out",
                          "logstash_stats_pipeline_plugin_bulk_requests_errors",
                          "logstash_stats_pipeline_plugin_documents_non_retryable_failures"}
FORBIDDEN =("payment_id", "customer_id", "token", "pan", "card")


def panels(doc):
    return [p for p in doc["panels"] if p["type"] != "row"]


# PromQL checks apply to the metric panels; Tempo panels have their own test.
def targets(p):
    return p["targets"] if p["datasource"]["type"] == "prometheus" else []


def tempo_panels(doc):
    return [p for p in panels(doc) if p["datasource"]["type"] == "tempo"]


class DashboardStandardTest(unittest.TestCase):
    def test_all_levels_present(self):
        uids = {d["uid"] for d in DOCS.values()}
        wanted = {"platform-overview", "slo-overview", "payments", "router", "locker", "drainer", "scheduler", "cells", "data-stores", "backup", "dr-switch", "cost", "kubernetes", "edge", "slow-requests", "logs"}
        self.assertEqual(wanted, uids)

    def test_committed_json_matches_generator(self):
        self.assertEqual(build.main(["--check"]), 0)

    def test_every_panel_has_title_unit_and_datasource(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                with self.subTest(dashboard=path.name, panel=p.get("title")):
                    self.assertTrue(p["title"])
                    self.assertTrue(p["fieldConfig"]["defaults"].get("unit"))
                    self.assertEqual(p["datasource"]["uid"], "tempo" if p["datasource"]["type"] == "tempo" else "${datasource}")

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
                        self.assertTrue(4 <= w <= 12, w)
                    else:
                        self.assertIn(w, (12, 24))

    def test_at_most_25_panels(self):
        for path, doc in DOCS.items():
            self.assertLessEqual(len(panels(doc)), 25, path.name)

    def test_queries_use_variables_and_legends(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in targets(p):
                    with self.subTest(dashboard=path.name, panel=p["title"]):
                        self.assertIn("$env", t["expr"])
                        if p["type"] in ("timeseries", "bargauge"):
                            self.assertTrue(t["legendFormat"], "legend must be a template, not raw labels")

    def test_rate_only_on_counters(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in targets(p):
                    for fn, metric in re.findall(r"\b(rate|increase)\(\s*([A-Za-z_:][A-Za-z0-9_:]*)", t["expr"]):
                        with self.subTest(dashboard=path.name, panel=p["title"], metric=metric):
                            if metric not in COUNTER_WITHOUT_SUFFIX:
                                self.assertRegex(metric, COUNTER)

    def test_latency_panels_use_quantiles_not_averages(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in targets(p):
                    if "duration" in t["expr"] or "latency" in t["expr"]:
                        self.assertNotRegex(t["expr"], r"\bavg(_over_time)?\(", f"{path.name}: {p['title']}")

    def test_standard_variables_and_defaults(self):
        for path, doc in DOCS.items():
            names = [v["name"] for v in doc["templating"]["list"]]
            self.assertEqual(names[:6], ["datasource", "env", "region", "cell", "service", "psp"], path.name)
            by = {v["name"]: v for v in doc["templating"]["list"]}
            self.assertEqual(by["env"]["current"]["text"], "prod")
            self.assertEqual(by["region"]["current"]["text"], "eu-central-1")
            self.assertFalse(doc["editable"])

    def test_no_high_cardinality_labels(self):
        for path, doc in DOCS.items():
            text = json.dumps([t["expr"] + t["legendFormat"] for p in panels(doc) for t in targets(p)])
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
                if link.get("url", "").startswith("/d/"):
                    self.assertIn(link["url"].split("/d/")[1].split("?")[0], uids, path.name)
            for p in panels(doc):
                for link in p["fieldConfig"]["defaults"].get("links", []):
                    self.assertIn(link["url"].split("/d/")[1].split("?")[0], uids, f"{path.name}: {p['title']}")

    def test_metrics_exist_in_catalog(self):
        catalog = set(json.loads((OBS / "coverage" / "metrics-catalog.json").read_text())["metrics"])
        _, recorded = cov.load_rules([OBS / "alerts", OBS / "slo" / "generated"])
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in targets(p):
                    for m in cov.extract_metrics(t["expr"]):
                        with self.subTest(dashboard=path.name, metric=m):
                            self.assertTrue(m in catalog or m in recorded or m == "ALERTS", m)


    def test_no_holes_in_the_grid(self):
        for path, doc in DOCS.items():
            bottom = max(p["gridPos"]["y"] + p["gridPos"]["h"] for p in doc["panels"])
            covered = {(x, y) for p in doc["panels"] for x in range(p["gridPos"]["x"], p["gridPos"]["x"] + p["gridPos"]["w"])
                       for y in range(p["gridPos"]["y"], p["gridPos"]["y"] + p["gridPos"]["h"])}
            holes = sorted({y for x in range(24) for y in range(bottom) if (x, y) not in covered})
            self.assertEqual(holes, [], f"{path.name}: empty cells on grid lines {holes}")

    def test_heights_by_type(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                with self.subTest(dashboard=path.name, panel=p["title"]):
                    self.assertIn(p["gridPos"]["h"], (4, 5) if p["type"] in STAT_KINDS else (8, 9))

    def test_first_row_answers_is_it_ok(self):
        for path, doc in DOCS.items():
            first = [p for p in doc["panels"] if p["gridPos"]["y"] == 1]
            with self.subTest(dashboard=path.name):
                self.assertTrue(first and all(p["type"] in STAT_KINDS for p in first))
                self.assertTrue(any(len(p["fieldConfig"]["defaults"]["thresholds"]["steps"]) > 1 for p in first))

    def test_stat_titles_fit_their_width(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                if p["type"] in STAT_KINDS:
                    self.assertLessEqual(len(p["title"]), 8 * p["gridPos"]["w"], f"{path.name}: {p['title']}")

    def test_titles_unique_and_level_prefixed(self):
        titles = [d["title"] for d in DOCS.values()]
        self.assertEqual(len(titles), len(set(titles)))
        for path, doc in DOCS.items():
            level = LEVEL[path.parent.name]
            self.assertTrue(doc["title"].startswith("FinOps" if level == "finops" else level.upper()), doc["title"])
            names = [p["title"] for p in panels(doc)]
            self.assertEqual(len(names), len(set(names)), f"{path.name} repeats a panel title")

    def test_stats_show_no_data_instead_of_a_colour(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                if p["type"] in STAT_KINDS:
                    d = p["fieldConfig"]["defaults"]
                    with self.subTest(dashboard=path.name, panel=p["title"]):
                        self.assertEqual(d.get("noValue"), "No data")
                        self.assertTrue(any(m["type"] == "special" and m["options"]["match"] == "null+nan" for m in d.get("mappings", [])))

    def test_every_panel_has_min(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                if p["type"] != "table":
                    self.assertIn("min", p["fieldConfig"]["defaults"], f"{path.name}: {p['title']}")

    def test_timeseries_tell_series_apart_and_draw_thresholds(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                if p["type"] != "timeseries":
                    continue
                d = p["fieldConfig"]["defaults"]
                with self.subTest(dashboard=path.name, panel=p["title"]):
                    self.assertEqual(d["color"]["mode"], "palette-classic")
                    drawn = d["custom"]["thresholdsStyle"]["mode"] != "off"
                    self.assertEqual(drawn, len(d["thresholds"]["steps"]) > 1)
                    self.assertEqual(p["options"]["tooltip"]["sort"], "desc")
                    self.assertIn(p["options"]["legend"]["displayMode"], ("table", "list"))
                    self.assertIn(p["options"]["legend"]["placement"], ("bottom", "right"))
                    for t in targets(p):
                        self.assertNotIn("{{", t["expr"])
                        self.assertNotRegex(t["legendFormat"], r"[({]\s*[a-z_]+\{|rate\(", "legend must name the series, not repeat the query")

    def test_range_queries_use_rate_interval(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                for t in targets(p):
                    if not t.get("instant"):
                        self.assertNotIn("[5m]", t["expr"], f"{path.name}: {p['title']}")

    def test_wide_group_bys_are_capped(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                if p["type"] != "timeseries":
                    continue
                for t in targets(p):
                    if WIDE_LABELS.search(t["expr"]) and "store" not in t["legendFormat"]:
                        self.assertRegex(t["expr"], r"^(topk|bottomk)\(8,", f"{path.name}: {p['title']}")

    def test_ratios_guard_against_division_by_zero(self):
        for path, doc in DOCS.items():
            for p in panels(doc):
                if p["fieldConfig"]["defaults"]["unit"] != "percent":
                    continue
                for t in targets(p):
                    if re.search(r"\) / [a-z(]", t["expr"]) and "_bytes" not in t["expr"] and "Disk" not in t["expr"]:
                        self.assertIn("> 0)", t["expr"], f"{path.name}: {p['title']}")

    def test_variables_readable_and_hidden_when_unused(self):
        for path, doc in DOCS.items():
            used = " ".join(t.get("expr") or t["query"] for p in panels(doc) for t in p["targets"])
            by = {v["name"]: v for v in doc["templating"]["list"]}
            self.assertFalse(by["env"]["multi"] or by["env"]["includeAll"], "one environment at a time")
            for v in by.values():
                with self.subTest(dashboard=path.name, variable=v["name"]):
                    self.assertNotEqual(v["label"], v["name"])
                    if v["type"] == "query":
                        self.assertEqual(v["sort"], 1)
                    if v.get("hide", 0) == 0 and v["name"] not in ("datasource", "env", "region"):
                        self.assertRegex(used, rf"\$\{{?{v['name']}\b")

    def test_time_and_refresh_by_level(self):
        for path, doc in DOCS.items():
            level = LEVEL[path.parent.name]
            with self.subTest(dashboard=path.name):
                if level in ("l0", "finops"):
                    self.assertEqual((doc["time"]["from"], doc["refresh"]), LEVEL_TIME[level])
                else:
                    self.assertIn(doc["time"]["from"], ("now-6h", "now-7d"))

    def test_navigation(self):
        for path, doc in DOCS.items():
            tags = doc["tags"]
            with self.subTest(dashboard=path.name):
                self.assertEqual(len(tags), len(set(tags)))
                self.assertEqual(tags[:2], ["payments-platform", LEVEL[path.parent.name]])
                self.assertTrue(any(link["type"] == "dashboards" and link["tags"] == ["payments-platform"] for link in doc["links"]))
                if doc["uid"] != "platform-overview":
                    self.assertIn("/d/platform-overview", [link.get("url") for link in doc["links"]])
                if doc["uid"] != "cost":
                    self.assertTrue(any(link.get("icon") == "doc" for link in doc["links"]), "runbook link")

    def test_alert_thresholds_drawn_in_the_severity_colour(self):
        rules = {}
        for f in (OBS / "alerts").rglob("*.yaml"):
            for g in yaml.safe_load(f.read_text())["spec"]["groups"]:
                rules.update({r["alert"]: r["labels"]["severity"] for r in g["rules"] if "alert" in r})
        drawn = []
        for doc in DOCS.values():
            for p in panels(doc):
                st = p["fieldConfig"]["defaults"]["thresholds"]["steps"]
                inverted = len(st) > 1 and st[-1]["color"] == "green" and st[0]["color"] != "green"
                drawn += [(st[i]["value"], st[i - 1]["color"] if inverted else st[i]["color"]) for i in range(1, len(st))]
        want = {"critical": "red", "warning": "yellow"}
        for alert, const in thresholds.ALERT_LINKS.items():
            value = getattr(thresholds, const)
            hits = [c for v, c in drawn if any(math.isclose(v, x) for x in (value, value * 100))]
            with self.subTest(alert=alert):
                self.assertIn(want[rules[alert]], hits)


class SlowRequestsDashboardTest(unittest.TestCase):
    DOC = json.loads((OBS / "dashboards" / "l1-services" / "slow-requests.json").read_text())

    def emitted_labels(self):
        cfg = yaml.safe_load((OBS / "otel" / "collector.yaml").read_text())
        dims = [d["name"] for d in cfg["connectors"]["span_metrics/slow"]["dimensions"]]
        stmts = [s for g in cfg["processors"]["transform/spanmetrics-labels"]["metric_statements"] for s in g["statements"]]
        renamed = dict(re.findall(r'set\(attributes\["([a-z_.]+)"\], (?:resource\.)?attributes\["([a-z_.]+)"\]\)', "\n".join(stmts)))
        out = {new for new, old in renamed.items()} | {d for d in dims if d not in renamed.values()}
        return out | set(cfg["exporters"]["prometheusremotewrite/central"]["external_labels"]) | {"le"}

    def test_queries_use_only_labels_the_collector_emits(self):
        allowed = self.emitted_labels()
        self.assertEqual(allowed, {"service", "route", "cell", "slow", "env", "region", "le"})
        for p in panels(self.DOC):
            for t in targets(p):
                used = set(re.findall(r"([a-z_]+)=~?\"", t["expr"])) | {l.strip() for by in re.findall(r"by \(([^)]*)\)", t["expr"]) for l in by.split(",")}
                with self.subTest(panel=p["title"], ref=t["refId"]):
                    self.assertLessEqual(used, allowed)
                    for m in cov.extract_metrics(t["expr"]):
                        self.assertTrue(m.startswith("slow_requests_"), m)

    def test_trace_tables_are_bounded_and_filtered(self):
        tables = tempo_panels(self.DOC)
        self.assertEqual(len(tables), 2)
        for p in tables:
            (t,) = p["targets"]
            with self.subTest(panel=p["title"]):
                self.assertEqual(p["datasource"], {"type": "tempo", "uid": "tempo"})
                self.assertEqual((t["queryType"], t["limit"]), ("traceql", 100))
                for part in ("span.slow = true", '"$env"', '"$route"', '"$cell"', '"$service"', "${threshold}ms"):
                    self.assertIn(part, t["query"])

    def test_group_rows_filter_the_trace_tables(self):
        (table,) = [p for p in panels(self.DOC) if p["type"] == "table" and p["datasource"]["type"] == "prometheus"]
        url = table["fieldConfig"]["defaults"]["links"][0]["url"]
        for var in ("service", "route", "cell"):
            self.assertIn(f"var-{var}=${{__data.fields.{var}}}", url)
        self.assertEqual(table["options"]["sortBy"][0]["displayName"], "Lost time")
        names = list(table["transformations"][1]["options"]["renameByName"].values())
        self.assertEqual(names, ["Slow requests", "Share of all, %", "p50", "p95", "Max (bucket bound)", "Last seen", "Lost time"])

    def test_the_l1_services_dashboards_link_here(self):
        for uid in ("router", "payments"):
            doc = json.loads((OBS / "dashboards" / "l1-services" / f"{uid}.json").read_text())
            self.assertIn("/d/slow-requests", [link.get("url") for link in doc["links"]], uid)

    def test_thresholds_in_the_description_follow_the_yaml(self):
        cfg = yaml.safe_load((OBS / "slo" / "config" / "slow-requests.yaml").read_text())
        for name, spec in cfg["types"].items():
            total = spec["threshold_ms"] + (cfg["psp_allowance_ms"] if spec["measure"] == "own" else 0)
            self.assertIn(f"{name} > {total} ms", self.DOC["description"])


if __name__ == "__main__":
    unittest.main()
