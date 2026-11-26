import io
import secrets
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from integration import api, fake_router, run  # noqa: E402

ADMIN = secrets.token_hex(8)


class Stack:
    def __init__(self, faults=()):
        self.state = fake_router.State(ADMIN, faults)
        self.srv = fake_router.serve(self.state)
        self.url = f"http://127.0.0.1:{self.srv.server_address[1]}"

    def run(self, **extra):
        env = {"INTEGRATION_API_URL": self.url, "INTEGRATION_ADMIN_API_KEY": ADMIN, **extra}
        out = io.StringIO()
        code = run.main([], env, out)
        return code, out.getvalue()

    def close(self):
        self.srv.shutdown()
        self.srv.server_close()


class ScenarioTest(unittest.TestCase):
    def stack(self, faults=()):
        s = Stack(faults)
        self.addCleanup(s.close)
        return s

    def test_green_stack_passes_and_skips_the_token_path(self):
        code, out = self.stack().run()
        self.assertEqual(code, 0, out)
        self.assertIn("scenario token-lifecycle: skip", out)
        self.assertNotIn(ADMIN, out)

    def test_token_lifecycle_reuses_the_smoke_shapes(self):
        code, out = self.stack().run(INTEGRATION_PAYMENT_TOKEN=fake_router.TOKEN)
        self.assertEqual(code, 0, out)
        self.assertIn("scenario token-lifecycle: ok", out)

    def test_each_fault_is_caught_by_its_scenario(self):
        cases = {"no_auth": "auth-required", "cancel_noop": "create-get-cancel",
                 "dup_ok": "duplicate-payment-id", "bad_shape": "create-get-cancel"}
        for fault, scenario in cases.items():
            with self.subTest(fault=fault):
                code, out = self.stack([fault]).run()
                self.assertEqual(code, 1)
                self.assertIn(f"scenario {scenario}: FAIL", out)

    def test_wrong_admin_key_fails_bootstrap(self):
        code, out = self.stack().run(INTEGRATION_ADMIN_API_KEY="wrong")
        self.assertEqual(code, 1)
        self.assertIn("bootstrap: FAIL create merchant: HTTP 401", out)

    def test_dead_health_url_fails(self):
        code, out = self.stack().run(INTEGRATION_HEALTH_URLS="http://127.0.0.1:9/health")
        self.assertEqual(code, 1)
        self.assertIn("scenario health: FAIL", out)


class GuardTest(unittest.TestCase):
    def test_unset_url_skips_only_when_asked(self):
        self.assertEqual(run.main(["--skip-unset"], {}, io.StringIO()), 0)
        self.assertEqual(run.main([], {}, io.StringIO()), 2)

    def test_plain_http_to_a_remote_host_is_refused(self):
        out = io.StringIO()
        self.assertEqual(run.main([], {"INTEGRATION_API_URL": "http://stage.example.com", "INTEGRATION_ADMIN_API_KEY": "x"}, out), 2)
        self.assertIn("plain http", out.getvalue())

    def test_compose_hosts_allow_http(self):
        self.assertEqual(api.check_url("http://router:8080", ("router",)), "router")

    def test_credentials_in_url_refused(self):
        with self.assertRaises(ValueError):
            api.check_url("https://u:p@stage.example.com")

    def test_real_connector_refused(self):
        out = io.StringIO()
        self.assertEqual(run.main([], {"INTEGRATION_API_URL": "https://x.example.com", "INTEGRATION_CONNECTOR": "adyen"}, out), 2)


class ContractTest(unittest.TestCase):
    def test_payment_contract(self):
        api.payment_contract({"payment_id": "p", "status": "x", "amount": 1, "currency": "EUR"})
        with self.assertRaises(api.Failed):
            api.payment_contract({"payment_id": "p", "status": "x", "amount": "1", "currency": "EUR"})

    def test_error_contract(self):
        api.error_contract({"error": {"type": "t", "message": "m", "code": "c"}})
        with self.assertRaises(api.Failed):
            api.error_contract({"message": "m"})


if __name__ == "__main__":
    unittest.main()
