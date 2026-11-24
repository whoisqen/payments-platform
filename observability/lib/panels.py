"""Panel and dashboard builders that enforce the dashboard standard checked by observability/lib/tests."""
from pathlib import Path

import yaml

COLORS = {"ok": "green", "warn": "yellow", "crit": "red", "info": "blue"}
DS = {"type": "prometheus", "uid": "${datasource}"}
F = 'env=~"$env",region=~"$region"'
FC = F + ',cell=~"$cell"'
RATE = "$__rate_interval"


def _runbook_base():
    """Runbooks are rendered by the repository host (there is no runbook site yet); the repository comes from the platform config."""
    cfg = yaml.safe_load((Path(__file__).resolve().parents[2] / "config" / "platform.yaml").read_text(encoding="utf-8"))
    return f"https://github.com/{cfg['owner']['github_org']}/{cfg['owner']['github_repo']}/tree/main/docs/runbooks"


RUNBOOK_BASE = _runbook_base()
HEIGHT = {"stat": 4, "gauge": 4}
WIDE_HEIGHT = 9
STAT_KINDS = ("stat", "gauge")
MAX_STATS_PER_BAND = 6
# Time range and refresh by level: L0 is watched live, FinOps data changes once a day.
LEVEL_TIME = {"l0": ("now-3h", "30s"), "l1": ("now-6h", "1m"), "l2": ("now-6h", "1m"), "l3": ("now-6h", "1m"), "finops": ("now-30d", "1h")}
NO_DATA = [{"type": "special", "options": {"match": "null+nan", "result": {"text": "No data", "color": "text", "index": 0}}}]


def steps(warn=None, crit=None, invert=False, info=False):
    if info:
        return [{"color": COLORS["info"], "value": None}]
    if invert:
        # Low is bad: red below crit, yellow below warn, green above.
        base = [{"color": COLORS["crit"] if crit is not None else COLORS["warn"], "value": None}]
        if crit is not None and warn is not None:
            base.append({"color": COLORS["warn"], "value": crit})
        base.append({"color": COLORS["ok"], "value": warn if warn is not None else crit})
        return base
    out = [{"color": COLORS["ok"], "value": None}]
    if warn is not None:
        out.append({"color": COLORS["warn"], "value": warn})
    if crit is not None:
        out.append({"color": COLORS["crit"], "value": crit})
    return out


def drill(uid, title, var=None):
    url = f"/d/{uid}?${{__url_time_range}}&${{env:queryparam}}&${{region:queryparam}}"
    if var:
        url += f"&var-{var}=${{__field.labels.{var}}}"
    return {"title": f"Open {title}", "url": url}


class Dashboard:
    def __init__(self, uid, title, level, tags, service=None, links=(), description="", runbooks=(), time=None):
        self.uid, self.title, self.level, self.tags = uid, title, level, tags
        self.service, self.links, self.description, self.runbooks = service, list(links), description, list(runbooks)
        self.time = time or LEVEL_TIME[level]
        self.items = []

    def row(self, title):
        self.items.append({"type": "row", "title": title, "collapsed": False, "panels": []})

    def _add(self, kind, w, body):
        self.items.append({"type": kind, "datasource": DS, "_w": w, **body})

    @staticmethod
    def _defaults(unit, lo, hi, thr, decimals, link=None):
        d = {"unit": unit, "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": thr or steps(info=True)}}
        if lo is not None:
            d["min"] = lo
        if hi is not None:
            d["max"] = hi
        if decimals is not None:
            d["decimals"] = decimals
        if link:
            d["links"] = [link]
        return d

    def _targets(self, queries, exemplar=False, instant=False):
        out = []
        for i, q in enumerate(queries):
            expr, legend = q if isinstance(q, tuple) else (q, "")
            t = {"refId": chr(65 + i), "expr": expr.replace("[5m]", f"[{RATE}]") if not instant else expr, "legendFormat": legend}
            if exemplar:
                t["exemplar"] = True
            if instant:
                t["instant"] = True
                t["range"] = False
            out.append(t)
        return out

    def stat(self, title, expr, unit, lo=0, hi=None, thr=None, desc="", decimals=None, mappings=None, link=None):
        if decimals is None:
            decimals = {"percent": 1, "short": 0, "s": 2}.get(unit)
        d = self._defaults(unit, lo, hi, thr, decimals, link)
        d["mappings"] = (mappings or []) + NO_DATA
        d["noValue"] = "No data"
        self._add("stat", 4, {"title": title, "description": desc, "targets": self._targets([expr], instant=True), "fieldConfig": {"defaults": d, "overrides": []},
                              "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "colorMode": "background", "graphMode": "none",
                                          "textMode": "value", "justifyMode": "center", "orientation": "auto"}})

    def gauge(self, title, expr, unit, lo, hi, thr, desc=""):
        d = self._defaults(unit, lo, hi, thr, 1)
        d["mappings"] = list(NO_DATA)
        d["noValue"] = "No data"
        self._add("gauge", 4, {"title": title, "description": desc, "targets": self._targets([expr], instant=True), "fieldConfig": {"defaults": d, "overrides": []},
                               "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}, "showThresholdMarkers": True, "showThresholdLabels": False}})

    def ts(self, title, queries, unit, w=12, lo=0, hi=None, thr=None, desc="", exemplar=False, decimals=None, link=None, overrides=None):
        d = self._defaults(unit, lo, hi, thr, decimals, link)
        d["color"] = {"mode": "palette-classic"}
        d["custom"] = {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 0, "showPoints": "never", "spanNulls": False, "axisPlacement": "auto",
                       "thresholdsStyle": {"mode": "dashed" if thr and len(thr) > 1 else "off"}}
        self._add("timeseries", w, {"title": title, "description": desc, "targets": self._targets(queries, exemplar=exemplar), "fieldConfig": {"defaults": d, "overrides": overrides or []},
                                    "options": {"legend": {"showLegend": True, "displayMode": "table", "placement": "bottom", "calcs": ["lastNotNull", "max"], "sortBy": "Max", "sortDesc": True},
                                                "tooltip": {"mode": "multi", "sort": "desc"}}})

    def bars(self, title, expr, legend, unit, w=12, lo=0, hi=None, thr=None, desc="", link=None):
        d = self._defaults(unit, lo, hi, thr, None, link)
        d["mappings"] = list(NO_DATA)
        self._add("bargauge", w, {"title": title, "description": desc, "targets": self._targets([(expr, legend)], instant=True), "fieldConfig": {"defaults": d, "overrides": []},
                                  "options": {"orientation": "horizontal", "displayMode": "basic", "valueMode": "color", "namePlacement": "left", "showUnfilled": True,
                                              "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}})

    def heatmap(self, title, expr, unit="s", w=12, desc=""):
        t = self._targets([(expr, "{{le}}")])
        t[0]["format"] = "heatmap"
        # The y axis carries the bucket unit; the cells are request counts.
        self._add("heatmap", w, {"title": title, "description": desc, "targets": t, "fieldConfig": {"defaults": self._defaults("short", 0, None, None, None), "overrides": []},
                                 "options": {"calculate": False, "yAxis": {"unit": unit, "axisPlacement": "left"}, "cellValues": {"unit": "short"},
                                             "color": {"mode": "scheme", "scheme": "Blues", "steps": 64}, "legend": {"show": True},
                                             "tooltip": {"mode": "single", "yHistogram": True}, "rowsFrame": {"layout": "auto"}}})

    def table(self, title, expr, unit="short", w=24, desc="", value_name="Value", mappings=None, thr=None):
        t = self._targets([expr], instant=True)
        t[0]["format"] = "table"
        d = self._defaults(unit, None, None, thr, None)
        if mappings:
            d["mappings"] = mappings
            d["custom"] = {"cellOptions": {"type": "color-background"}}
        self._add("table", w, {"title": title, "description": desc, "targets": t, "fieldConfig": {"defaults": d, "overrides": []},
                               "options": {"showHeader": True, "sortBy": [{"displayName": value_name, "desc": True}]},
                               "transformations": [{"id": "organize", "options": {"excludeByName": {"Time": True}, "renameByName": {"Value": value_name}}}]})

    def _layout(self):
        sections, cur = [], None
        for item in self.items:
            if item["type"] == "row":
                cur = (item, [])
                sections.append(cur)
            else:
                if cur is None:
                    cur = (None, [])
                    sections.append(cur)
                cur[1].append(item)
        out, y, ident = [], 0, 0
        for row, items in sections:
            if row is not None:
                ident += 1
                out.append({"id": ident, **row, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}})
                y += 1
            groups = []
            for p in items:
                stat = p["type"] in STAT_KINDS
                if groups and groups[-1][0] == stat:
                    groups[-1][1].append(p)
                else:
                    groups.append((stat, [p]))
            for stat, group in groups:
                lines = [group[i:i + MAX_STATS_PER_BAND] for i in range(0, len(group), MAX_STATS_PER_BAND)] if stat else self._pack(group)
                for line in lines:
                    widths = self._widths(line, stat)
                    x, h = 0, max(HEIGHT.get(p["type"], WIDE_HEIGHT) for p in line)
                    for p, w in zip(line, widths):
                        ident += 1
                        body = {k: v for k, v in p.items() if k != "_w"}
                        out.append({"id": ident, "type": body.pop("type"), "datasource": body.pop("datasource"), "gridPos": {"x": x, "y": y, "w": w, "h": h}, **body})
                        x += w
                    y += h
        return out

    @staticmethod
    def _pack(group):
        lines, line, used = [], [], 0
        for p in group:
            if used + p["_w"] > 24:
                lines.append(line)
                line, used = [], 0
            line.append(p)
            used += p["_w"]
        if line:
            lines.append(line)
        return lines

    @staticmethod
    def _widths(line, stat):
        if stat:
            base, extra = divmod(24, len(line))
            return [base + (1 if i < extra else 0) for i in range(len(line))]
        # A lone half-width panel takes the whole line so no half row stays empty.
        return [24] if len(line) == 1 else [p["_w"] for p in line]

    def variables(self, used):
        def query(name, label, q, current, multi=True, include_all=True):
            v = {"name": name, "label": label, "type": "query", "datasource": DS, "query": f"label_values({q})", "refresh": 2, "sort": 1, "multi": multi,
                 "includeAll": include_all, "current": {"text": current, "value": current if current != "All" else "$__all"}, "hide": 0 if f"${name}" in used else 2}
            if include_all:
                v["allValue"] = ".*"
            return v
        svc = self.service or "All"
        service = query("service", "Service", 'up{env=~"$env"}, service', svc)
        if self.service:
            service["hide"] = 2
        return [
            {"name": "datasource", "label": "Data source", "type": "datasource", "query": "prometheus", "hide": 0, "current": {"text": "default", "value": "default"}},
            query("env", "Environment", "up, env", "prod", multi=False, include_all=False),
            query("region", "Region", 'up{env=~"$env"}, region', "eu-central-1"),
            query("cell", "Cell", 'up{env=~"$env",region=~"$region"}, cell', "All"),
            service,
            query("psp", "PSP", 'psp_requests_total{env=~"$env",region=~"$region"}, psp', "All"),
        ]

    def build(self):
        panels = self._layout()
        used = " ".join(t["expr"] for p in panels for t in p.get("targets", []))
        links = [{"type": "link", "title": t, "url": f"/d/{u}", "icon": "dashboard", "targetBlank": False, "keepTime": True, "includeVars": True} for u, t in self.links]
        links.append({"type": "dashboards", "title": "All dashboards", "tags": ["payments-platform"], "asDropdown": True, "keepTime": True, "includeVars": True, "targetBlank": False})
        links += [{"type": "link", "title": f"Runbooks: {area}", "url": f"{RUNBOOK_BASE}/{area}", "icon": "doc", "targetBlank": True} for area in self.runbooks]
        tags = list(dict.fromkeys(["payments-platform", self.level, *self.tags]))
        return {
            "uid": self.uid, "title": self.title, "description": self.description, "tags": tags,
            "timezone": "utc", "schemaVersion": 39, "version": 1, "editable": False, "graphTooltip": 1, "refresh": self.time[1], "liveNow": False, "weekStart": "",
            "fiscalYearStartMonth": 0, "time": {"from": self.time[0], "to": "now"},
            "templating": {"list": self.variables(used)},
            "links": links,
            "annotations": {"list": [{"name": "deploys", "datasource": DS, "enable": True, "iconColor": COLORS["info"], "expr": 'increase(argocd_app_sync_total{env=~"$env",phase="Succeeded"}[2m]) > 0', "titleFormat": "deploy {{name}}"}]},
            "panels": panels,
        }
