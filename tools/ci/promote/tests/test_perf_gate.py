import io
import json
import sys
import unittest
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import perf_gate as pg  # noqa: E402


class FakeOpener:
    def __init__(self, p99, failed, status="success"):
        self.values = {"duration": p99, "failed": failed}
        self.status, self.seen = status, []

    def open(self, req, timeout=None):
        q = urllib.parse.parse_qs(urllib.parse.urlsplit(req.full_url).query)["query"][0]
        self.seen.append((q, req.headers.get("Authorization")))
        vals = self.values["duration" if "duration" in q else "failed"]
        body = {"status": self.status, "data": {"result": [{"value": [0, str(v)]} for v in vals]}}
        return _Resp(json.dumps(body).encode())


class _Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


BASE = {"PERF_VM_URL": "https://vm.example.com"}


class PerfGateTest(unittest.TestCase):
    def run_gate(self, opener, **env):
        out = io.StringIO()
        return pg.main({**BASE, **env}, opener, out), out.getvalue()

    def test_unset_url_skips(self):
        out = io.StringIO()
        self.assertEqual(pg.main({}, None, out), 0)
        self.assertIn("skipped", out.getvalue())

    def test_within_limits_passes(self):
        code, out = self.run_gate(FakeOpener([0.8], [0.001]))
        self.assertEqual(code, 0, out)

    def test_slow_run_fails(self):
        code, out = self.run_gate(FakeOpener([2.5], [0.0]))
        self.assertEqual(code, 1)
        self.assertIn("p99", out)

    def test_error_rate_fails(self):
        self.assertEqual(self.run_gate(FakeOpener([0.1], [0.2]))[0], 1)

    def test_no_recent_run_fails(self):
        code, out = self.run_gate(FakeOpener([], []))
        self.assertEqual(code, 1)
        self.assertIn("no k6 result", out)

    def test_selector_injection_refused(self):
        code, out = self.run_gate(FakeOpener([0.1], [0.0]), PERF_SELECTOR='a="b"}) or vector(0')
        self.assertEqual(code, 1)
        self.assertIn("bad PERF_SELECTOR", out)

    def test_plain_http_only_in_cluster(self):
        self.assertEqual(self.run_gate(FakeOpener([0.1], [0.0]), PERF_VM_URL="http://vm.example.com")[0], 1)
        self.assertEqual(self.run_gate(FakeOpener([0.1], [0.0]), PERF_VM_URL="http://vm.monitoring.svc")[0], 0)

    def test_token_sent_and_never_printed(self):
        opener = FakeOpener([0.1], [0.0])
        code, out = self.run_gate(opener, PERF_VM_TOKEN="tok123")
        self.assertEqual(code, 0)
        self.assertEqual(opener.seen[0][1], "Bearer tok123")
        self.assertNotIn("tok123", out)

    def test_failed_query_fails(self):
        self.assertEqual(self.run_gate(FakeOpener([0.1], [0.0], status="error"))[0], 1)


if __name__ == "__main__":
    unittest.main()
