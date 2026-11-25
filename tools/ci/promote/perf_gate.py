#!/usr/bin/env python3
"""Stage perf gate: reads the latest k6 TestRun result from VictoriaMetrics and fails above the limits.

Environment: PERF_VM_URL (unset: the gate is skipped), PERF_VM_TOKEN (optional bearer),
PERF_SELECTOR (default testid=~"stage-.*"), PERF_WINDOW (default 24h), PERF_MAX_P99_SECONDS (2.0),
PERF_MAX_FAILED_RATE (0.01). The k6 Operator writes k6_http_req_duration_p99 and k6_http_req_failed_rate
through Prometheus remote write.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

SELECTOR = re.compile(r'^[a-zA-Z_][a-zA-Z0-9_]*(=~|!~|!=|=)"[^"\\{}]*"(,[a-zA-Z_][a-zA-Z0-9_]*(=~|!~|!=|=)"[^"\\{}]*")*$')
WINDOW = re.compile(r"^[0-9]+[mhd]$")


class GateError(Exception):
    pass


def check_url(url):
    p = urllib.parse.urlsplit(url)
    host = (p.hostname or "").lower()
    if p.username or p.password or p.scheme not in ("http", "https"):
        raise GateError("PERF_VM_URL must be http(s) without credentials")
    if p.scheme == "http" and not host.endswith((".svc", ".svc.cluster.local")):
        raise GateError("plain http only to a cluster-local VictoriaMetrics")


def query(base, expr, token=None, opener=None):
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
    url = base.rstrip("/") + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        with opener.open(urllib.request.Request(url, headers=headers), timeout=20) as r:
            body = json.loads(r.read(1 << 20))
    except urllib.error.HTTPError as err:
        raise GateError(f"VictoriaMetrics HTTP {err.code}") from None
    except (OSError, ValueError) as err:
        raise GateError(f"VictoriaMetrics request failed: {type(err).__name__}") from None
    if body.get("status") != "success":
        raise GateError("VictoriaMetrics query did not succeed")
    try:
        return [float(s["value"][1]) for s in body["data"]["result"]]
    except (KeyError, IndexError, TypeError, ValueError):
        raise GateError("unexpected VictoriaMetrics response shape") from None


def evaluate(p99, failed, max_p99, max_failed):
    errors = []
    if not p99 or not failed:
        errors.append("no k6 result in the window: run the stage load test first")
        return errors
    if max(p99) > max_p99:
        errors.append(f"p99 {max(p99):.3f}s above {max_p99}s")
    if max(failed) > max_failed:
        errors.append(f"failed rate {max(failed):.4f} above {max_failed}")
    return errors


def main(environ=None, opener=None, out=None):
    e = os.environ if environ is None else environ
    out = sys.stdout if out is None else out
    base = e.get("PERF_VM_URL", "")
    if not base:
        print("perf gate: PERF_VM_URL is not set, skipped", file=out)
        return 0
    try:
        check_url(base)
        selector = e.get("PERF_SELECTOR") or 'testid=~"stage-.*"'
        window = e.get("PERF_WINDOW") or "24h"
        if not SELECTOR.match(selector) or not WINDOW.match(window):
            raise GateError("bad PERF_SELECTOR or PERF_WINDOW")
        max_p99 = float(e.get("PERF_MAX_P99_SECONDS") or 2.0)
        max_failed = float(e.get("PERF_MAX_FAILED_RATE") or 0.01)
        token = e.get("PERF_VM_TOKEN") or None
        p99 = query(base, f"max(last_over_time(k6_http_req_duration_p99{{{selector}}}[{window}]))", token, opener)
        failed = query(base, f"max(last_over_time(k6_http_req_failed_rate{{{selector}}}[{window}]))", token, opener)
    except (GateError, ValueError) as err:
        print(f"perf gate: FAIL {err}", file=out)
        return 1
    errors = evaluate(p99, failed, max_p99, max_failed)
    for x in errors:
        print(f"perf gate: FAIL {x}", file=out)
    if not errors:
        print(f"perf gate: ok p99 {max(p99):.3f}s, failed rate {max(failed):.4f}", file=out)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
