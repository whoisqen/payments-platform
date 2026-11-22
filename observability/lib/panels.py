"""Panel and dashboard builders that enforce the standard of observability/standards/dashboards.md."""

COLORS = {"ok": "green", "warn": "yellow", "crit": "red", "info": "blue"}
DS = {"type": "prometheus", "uid": "${datasource}"}
F = 'env=~"$env",region=~"$region"'
FC = F + ',cell=~"$cell"'
WIDTH = {"stat": 4, "gauge": 4}


def steps(warn=None, crit=None, invert=False, info=False):
    if info:
        return [{"color": COLORS["info"], "value": None}]
    if invert:
        base = [{"color": COLORS["crit"], "value": None}]
        if crit is not None:
            base.append({"color": COLORS["warn"], "value": crit})
        base.append({"color": COLORS["ok"], "value": warn})
        return base
    out = [{"color": COLORS["ok"], "value": None}]
    if warn is not None:
        out.append({"color": COLORS["warn"], "value": warn})
    if crit is not None:
        out.append({"color": COLORS["crit"], "value": crit})
    return out


class Dashboard:
    def __init__(self, uid, title, level, tags, service=None, links=(), description=""):
        self.uid, self.title, self.level, self.tags = uid, title, level, tags
        self.service, self.links, self.description = service, list(links), description
        self.panels, self._id, self._x, self._y, self._rowh = [], 0, 0, 0, 0

    def _next(self):
        self._id += 1
        return self._id

    def row(self, title):
        self._y += self._rowh
        self._x, self._rowh = 0, 0
        self.panels.append({"id": self._next(), "type": "row", "title": title, "collapsed": False, "gridPos": {"x": 0, "y": self._y, "w": 24, "h": 1}, "panels": []})
        self._y += 1

    def _place(self, kind, w, h, body):
        w = WIDTH.get(kind, w)
        if self._x + w > 24:
            self._y += self._rowh
            self._x, self._rowh = 0, 0
        panel = {"id": self._next(), "type": kind, "datasource": DS, "gridPos": {"x": self._x, "y": self._y, "w": w, "h": h}, **body}
        self._x += w
        self._rowh = max(self._rowh, h)
        self.panels.append(panel)

    @staticmethod
    def _defaults(unit, lo, hi, thr, decimals):
        d = {"unit": unit, "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": thr or steps(info=True)}}
        if lo is not None:
            d["min"] = lo
        if hi is not None:
            d["max"] = hi
        if decimals is not None:
            d["decimals"] = decimals
        return d

    def _targets(self, queries, exemplar=False, instant=False):
        out = []
        for i, q in enumerate(queries):
            expr, legend = q if isinstance(q, tuple) else (q, "")
            t = {"refId": chr(65 + i), "expr": expr, "legendFormat": legend}
            if exemplar:
                t["exemplar"] = True
            if instant:
                t["instant"] = True
            out.append(t)
        return out

    def stat(self, title, expr, unit, lo=None, hi=None, thr=None, desc="", decimals=None, mappings=None):
        d = self._defaults(unit, lo, hi, thr, decimals)
        if mappings:
            d["mappings"] = mappings
        self._place("stat", 4, 4, {"title": title, "description": desc, "targets": self._targets([expr], instant=True), "fieldConfig": {"defaults": d, "overrides": []},
                                   "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none"}})

    def gauge(self, title, expr, unit, lo, hi, thr, desc=""):
        d = self._defaults(unit, lo, hi, thr, 1)
        self._place("gauge", 4, 4, {"title": title, "description": desc, "targets": self._targets([expr], instant=True), "fieldConfig": {"defaults": d, "overrides": []},
                                    "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "showThresholdMarkers": True}})

    def ts(self, title, queries, unit, w=12, lo=None, hi=None, thr=None, desc="", exemplar=False, decimals=None):
        d = self._defaults(unit, lo, hi, thr, decimals)
        self._place("timeseries", w, 8, {"title": title, "description": desc, "targets": self._targets(queries, exemplar=exemplar), "fieldConfig": {"defaults": d, "overrides": []},
                                         "options": {"legend": {"displayMode": "table", "placement": "bottom", "calcs": ["lastNotNull", "max"]}, "tooltip": {"mode": "multi"}}})

    def bars(self, title, expr, legend, unit, w=12, lo=None, hi=None, thr=None, desc=""):
        d = self._defaults(unit, lo, hi, thr, None)
        self._place("barchart", w, 8, {"title": title, "description": desc, "targets": self._targets([(expr, legend)], instant=True), "fieldConfig": {"defaults": d, "overrides": []},
                                       "options": {"orientation": "horizontal", "legend": {"displayMode": "list"}}})

    def heatmap(self, title, expr, unit="s", w=12, desc=""):
        t = self._targets([(expr, "{{le}}")])
        t[0]["format"] = "heatmap"
        self._place("heatmap", w, 8, {"title": title, "description": desc, "targets": t, "fieldConfig": {"defaults": self._defaults(unit, None, None, None, None), "overrides": []},
                                      "options": {"calculate": False, "color": {"scheme": "Blues"}}})

    def table(self, title, expr, unit="short", w=24, desc=""):
        t = self._targets([expr], instant=True)
        t[0]["format"] = "table"
        self._place("table", w, 8, {"title": title, "description": desc, "targets": t, "fieldConfig": {"defaults": self._defaults(unit, None, None, None, None), "overrides": []},
                                    "transformations": [{"id": "organize", "options": {"excludeByName": {"Time": True}}}]})

    def variables(self):
        def query(name, label, current, multi=True, include_all=True):
            return {"name": name, "label": name, "type": "query", "datasource": DS, "query": f"label_values({label})", "refresh": 2, "sort": 1, "multi": multi,
                    "includeAll": include_all, "allValue": ".*", "current": {"text": current, "value": current if current != "All" else "$__all"}}
        svc = self.service or "All"
        return [
            {"name": "datasource", "label": "datasource", "type": "datasource", "query": "prometheus", "current": {"text": "default", "value": "default"}},
            query("env", "up, env", "prod"),
            query("region", f'up{{env=~"$env"}}, region', "eu-central-1"),
            query("cell", f'up{{env=~"$env",region=~"$region"}}, cell', "All"),
            query("service", f'up{{env=~"$env"}}, service', svc),
            query("psp", f'psp_requests_total{{env=~"$env"}}, psp', "All"),
        ]

    def build(self):
        return {
            "uid": self.uid, "title": self.title, "description": self.description, "tags": ["payments-platform", self.level, *self.tags],
            "timezone": "utc", "schemaVersion": 39, "version": 1, "editable": False, "graphTooltip": 1, "refresh": "30s",
            "time": {"from": "now-6h", "to": "now"},
            "templating": {"list": self.variables()},
            "links": [{"type": "link", "title": t, "url": f"/d/{u}", "icon": "dashboard", "targetBlank": False} for u, t in self.links],
            "annotations": {"list": [{"name": "deploys", "datasource": DS, "enable": True, "iconColor": COLORS["info"], "expr": 'changes(argocd_app_info{env=~"$env"}[1m]) > 0', "titleFormat": "deploy {{name}}"}]},
            "panels": self.panels,
        }
