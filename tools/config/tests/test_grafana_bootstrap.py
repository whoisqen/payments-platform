import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "deploy" / "platform" / "grafana" / "scripts"))
import bootstrap_orgs as boot  # noqa: E402

WANTED = [{"id": 1, "name": "Main Org."}, {"id": 2, "name": "Engineering"}, {"id": 3, "name": "Finance"}]


class FakeApi:
    """Grafana /api/orgs in memory; ids are handed out in sequence like the real one."""

    def __init__(self, orgs, next_id=None):
        self.orgs = [dict(o) for o in orgs]
        self.next_id = next_id or max((o["id"] for o in orgs), default=0) + 1
        self.calls = []

    def call(self, method, path, body=None):
        self.calls.append((method, path))
        if (method, path) == ("GET", "/api/orgs"):
            return [dict(o) for o in self.orgs]
        if (method, path) == ("POST", "/api/orgs"):
            org = {"id": self.next_id, "name": body["name"]}
            self.next_id += 1
            self.orgs.append(org)
            return {"orgId": org["id"], "message": "Organization created"}
        raise AssertionError((method, path))


class PlanTest(unittest.TestCase):
    def test_creates_the_missing_organizations_in_id_order(self):
        api = FakeApi([WANTED[0]])
        self.assertEqual(boot.run(api, WANTED[::-1], log=lambda _: None), 0)
        self.assertEqual([(o["id"], o["name"]) for o in api.orgs], [(1, "Main Org."), (2, "Engineering"), (3, "Finance")])

    def test_a_second_run_changes_nothing(self):
        api = FakeApi(WANTED)
        boot.run(api, WANTED, log=lambda _: None)
        self.assertNotIn(("POST", "/api/orgs"), api.calls)

    def test_dry_run_creates_nothing(self):
        api = FakeApi([WANTED[0]])
        lines = []
        boot.run(api, WANTED, dry_run=True, log=lines.append)
        self.assertNotIn(("POST", "/api/orgs"), api.calls)
        self.assertEqual(len([line for line in lines if "would create" in line]), 2)

    def test_a_name_on_another_id_fails(self):
        with self.assertRaises(boot.BootstrapError):
            boot.run(FakeApi([WANTED[0], {"id": 2, "name": "Other"}]), WANTED, log=lambda _: None)
        with self.assertRaises(boot.BootstrapError):
            boot.run(FakeApi([WANTED[0], {"id": 5, "name": "Finance"}]), WANTED, log=lambda _: None)

    def test_an_id_that_cannot_be_filled_in_fails_before_anything_is_created(self):
        api = FakeApi([WANTED[0], WANTED[2]])
        with self.assertRaises(boot.BootstrapError):
            boot.run(api, WANTED, log=lambda _: None)
        self.assertNotIn(("POST", "/api/orgs"), api.calls)

    def test_another_id_than_expected_fails_loudly(self):
        with self.assertRaises(boot.BootstrapError):
            boot.run(FakeApi([WANTED[0]], next_id=7), WANTED, log=lambda _: None)

    def test_a_repeated_id_in_the_config_fails(self):
        with self.assertRaises(boot.BootstrapError):
            boot.plan([], [WANTED[0], {"id": 1, "name": "Again"}])


class MainTest(unittest.TestCase):
    def run_main(self, env, opener, args=()):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "orgs.json"
            path.write_text(json.dumps({"orgs": WANTED}), encoding="utf-8")
            return boot.main(["--orgs", str(path), *args], env=env, opener=opener, sleep=lambda _: None)

    def test_missing_credentials_stop_the_run(self):
        self.assertEqual(self.run_main({}, None), 2)

    def test_the_password_goes_only_into_the_authorization_header(self):
        seen = []

        class Response:
            def __init__(self, body):
                self.body = body

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return self.body

        def opener(request, timeout):
            seen.append((request.get_method(), request.full_url, request.get_header("Authorization"), request.data))
            return Response(json.dumps([dict(o) for o in WANTED]).encode() if request.full_url.endswith("/api/orgs") else b"{}")

        env = {"GRAFANA_ADMIN_USER": "admin", "GRAFANA_ADMIN_PASSWORD": "s3cret-value", "GRAFANA_URL": "http://grafana.test"}
        self.assertEqual(self.run_main(env, opener, ["--dry-run"]), 0)
        self.assertTrue(all(url.startswith("http://grafana.test/") and "s3cret" not in url for _, url, _, _ in seen))
        self.assertTrue(all(auth.startswith("Basic ") for _, _, auth, _ in seen))
        self.assertTrue(all(data is None or b"s3cret" not in data for *_, data in seen))


if __name__ == "__main__":
    unittest.main()
