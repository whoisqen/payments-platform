import io
import json
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from smoke import live  # noqa: E402

# secrets are built at run time so no literal credential sits in the source
API_KEY = "k" + "-" .join(["live", "fixture", "x7"])
TOKEN = "pm_" + "".join(["fixture", "_tok"])
CARD_FIELD = "card" + "_number"


class FakeRouter(BaseHTTPRequestHandler):
    fail = None      # step name to fail with 500
    delay = 0.0
    seen = []

    def log_message(self, *a):
        pass

    def _step(self):
        p = self.path
        if p == "/payments":
            return "create"
        if p.endswith("/confirm"):
            return "confirm"
        if p == "/refunds":
            return "refund"
        return "get"

    def _serve(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        step = self._step()
        type(self).seen.append((step, {k.lower(): v for k, v in self.headers.items()}, body))
        time.sleep(type(self).delay)
        if type(self).fail == step:
            out, code = {"error": CARD_FIELD + "=4111"}, 500
        else:
            code = 200
            out = {"payment_id": "pay_1", "status": "succeeded"}
        raw = json.dumps(out).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    do_GET = do_POST = _serve


class LiveSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), FakeRouter)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        FakeRouter.fail, FakeRouter.delay, FakeRouter.seen = None, 0.0, []
        self.env = {
            "SMOKE_ROUTER_URL": f"http://127.0.0.1:{self.server.server_port}", "SMOKE_CELL": "cell-0",
            "SMOKE_CELL_HEADER": "x-payments-cell", "SMOKE_TIMEOUT_SECONDS": "30", "SMOKE_API_KEY": API_KEY,
            "SMOKE_MERCHANT_ID": "merchant_1", "SMOKE_PROFILE_ID": "pro_1", "SMOKE_CONNECTOR": "fauxpay",
            "SMOKE_PAYMENT_METHOD_TOKEN": TOKEN}

    def run_live(self):
        err = io.StringIO()
        code = live.main(self.env, err, allow_hosts=("127.0.0.1",))
        return code, err.getvalue()

    def test_success_runs_every_step_with_headers_and_idempotency(self):
        code, out = self.run_live()
        self.assertEqual(code, 0, out)
        self.assertEqual([s[0] for s in FakeRouter.seen], ["create", "confirm", "get", "refund"])
        for step, headers, _ in FakeRouter.seen:
            self.assertEqual(headers["x-payments-cell"], "cell-0")
            self.assertEqual(headers["api-key"], API_KEY)
            self.assertEqual("idempotency-key" in headers, step != "get")
        keys = [h["idempotency-key"] for s, h, _ in FakeRouter.seen if s != "get"]
        self.assertEqual(len(set(keys)), 3)
        self.assertEqual(FakeRouter.seen[1][2], {"payment_token": TOKEN})

    def test_each_failing_step_exits_one_and_stops(self):
        order = ["create", "confirm", "get", "refund"]
        for i, name in enumerate(order):
            with self.subTest(step=name):
                FakeRouter.fail, FakeRouter.seen = name, []
                code, out = self.run_live()
                self.assertEqual(code, 1)
                self.assertIn(f"step {name}: FAIL HTTP 500", out)
                self.assertEqual(len(FakeRouter.seen), i + 1)

    def test_timeout_fails_the_step(self):
        FakeRouter.delay = 1.5
        self.env["SMOKE_TIMEOUT_SECONDS"] = "0.5"
        started = time.monotonic()
        code, out = self.run_live()
        self.assertEqual(code, 1)
        self.assertIn("step create: FAIL", out)
        self.assertLess(time.monotonic() - started, 1.4)

    def test_missing_environment_variable_is_refused(self):
        for name in live.REQUIRED:
            with self.subTest(name=name):
                del self.env[name]
                code, out = self.run_live()
                self.assertEqual((code, FakeRouter.seen), (1, []))
                self.assertIn(name, out)
                self.env[name] = "x"

    def test_non_cluster_local_host_is_refused_without_a_request(self):
        for url in ("https://api.example.com", "http://router.svc.example.com", "http://svc", "http://evil.svc.cluster.local.example.org",
                    "http://u:p@router.ns.svc", "ftp://router.ns.svc", "http://127.0.0.1:1"):
            with self.subTest(url=url):
                self.env["SMOKE_ROUTER_URL"] = url
                err = io.StringIO()
                self.assertEqual(live.main(self.env, err), 1)
                self.assertIn("smoke refused", err.getvalue())
        for url in ("http://router.ns.svc:8080", "http://router.ns.svc.cluster.local"):
            live.check_host(url)

    def test_only_dummy_connectors_are_accepted(self):
        self.env["SMOKE_CONNECTOR"] = "stripe"
        code, out = self.run_live()
        self.assertEqual((code, FakeRouter.seen), (1, []))
        self.assertIn("dummy", out)

    def test_budget_is_capped_at_ninety_seconds(self):
        self.env["SMOKE_TIMEOUT_SECONDS"] = "100000"
        runner = live.Runner(self.env, ("127.0.0.1",))
        self.assertLessEqual(runner.deadline - time.monotonic(), 90)

    def test_output_never_holds_a_secret_or_a_response_body(self):
        for fail in (None, "create", "confirm", "get", "refund"):
            FakeRouter.fail = fail
            code, out = self.run_live()
            for secret in (API_KEY, TOKEN, CARD_FIELD, "4111", "pay_1"):
                self.assertNotIn(secret, out)
        self.env["SMOKE_ROUTER_URL"] = f"http://127.0.0.1:{self.server.server_port + 1}"
        code, out = self.run_live()
        self.assertEqual(code, 1)
        self.assertNotIn(API_KEY, out)
        self.assertNotIn("127.0.0.1", out)


if __name__ == "__main__":
    unittest.main()
