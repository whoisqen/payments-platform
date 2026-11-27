import re
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from contracts import model  # noqa: E402
from fakes import TOKEN, FakeEdge  # noqa: E402

BUDGET_SECONDS = 90
START = time.monotonic()


def edges():
    for env in model.environments():
        for region in model.regions(env):
            f = model.ENVS / env / region / "edge" / "values.yaml"
            if f.is_file():
                yield env, region, model.layered(env, region, "edge")[1]


def lifecycle(edge, cell, host, key):
    h = {edge.header: cell, "idempotency-key": key}
    body = {"amount": 1000, "currency": "EUR", "payment_method_token": TOKEN}
    code, pay = edge.request(host, "POST", "/payments", body, h)
    assert code == 201 and pay["status"] == "requires_capture", (code, pay)
    pid = pay["id"]
    steps = [("POST", f"/payments/{pid}/capture", "succeeded"), ("GET", f"/payments/{pid}", "succeeded"),
             ("POST", f"/payments/{pid}/refund", "refunded")]
    for method, path, status in steps:
        code, out = edge.request(host, method, path, {}, h)
        assert code == 200 and out["status"] == status, (method, path, code, out)
    return pid


class SyntheticPayment(unittest.TestCase):
    @classmethod
    def tearDownClass(cls):
        assert time.monotonic() - START <= BUDGET_SECONDS, "smoke suite exceeded its 90 second budget"

    def test_every_cell_of_every_edge_completes_the_lifecycle(self):
        seen = 0
        for env, region, values in edges():
            edge = FakeEdge(values)
            host = values["gateway"]["hosts"][0]
            for cell in edge.routes:
                with self.subTest(env=env, region=region, cell=cell):
                    pid = lifecycle(edge, cell, host, f"{env}-{cell}")
                    self.assertIn(f"_{cell}_", pid)
                    seen += 1
        self.assertGreaterEqual(seen, 10)

    def test_payment_stays_in_the_routed_cell(self):
        for env, region, values in edges():
            edge = FakeEdge(values)
            host = values["gateway"]["hosts"][0]
            lifecycle(edge, "cell-0", host, "k")
            others = sum(len(c.payments) for n, c in edge.cells.items() if n != "cell-0")
            self.assertEqual(others, 0, env)

    def test_routing_rejects_unknown_host_cell_and_declined_token(self):
        for env, region, values in edges():
            edge = FakeEdge(values)
            host = values["gateway"]["hosts"][0]
            body = {"amount": 1, "payment_method_token": TOKEN}
            self.assertEqual(edge.request("evil.example.test", "POST", "/payments", body, {edge.header: "cell-0"})[0], 404)
            self.assertEqual(edge.request(host, "POST", "/payments", body, {})[0], 421)
            self.assertEqual(edge.request(host, "POST", "/payments", body, {edge.header: "cell-9"})[0], 421)
            bad = {"amount": 1, "payment_method_token": "pm_other"}
            self.assertEqual(edge.request(host, "POST", "/payments", bad, {edge.header: "spare"})[0], 402)

    def test_idempotent_replay_returns_the_same_payment(self):
        for env, region, values in edges():
            edge = FakeEdge(values)
            host = values["gateway"]["hosts"][0]
            h = {edge.header: "spare", "idempotency-key": "same"}
            body = {"amount": 5, "payment_method_token": TOKEN}
            first = edge.request(host, "POST", "/payments", body, h)[1]
            second = edge.request(host, "POST", "/payments", body, h)[1]
            self.assertEqual(first["id"], second["id"])
            self.assertEqual(len(edge.cells["spare"].payments), 1)

    def test_invalid_state_transitions_are_refused(self):
        for env, region, values in edges():
            edge = FakeEdge(values)
            host = values["gateway"]["hosts"][0]
            h = {edge.header: "cell-0"}
            pid = edge.request(host, "POST", "/payments", {"amount": 5, "payment_method_token": TOKEN}, h)[1]["id"]
            self.assertEqual(edge.request(host, "POST", f"/payments/{pid}/refund", {}, h)[0], 409)

    def test_routing_matches_cell_directories_and_hosts(self):
        for env, region, values in edges():
            routed = [c["name"] for c in values["routing"]["cells"]]
            on_disk = sorted(p.name for p in (model.ENVS / env / region).iterdir() if re.fullmatch(r"cell-\d|spare", p.name))
            self.assertEqual(sorted(routed), on_disk, f"{env}/{region}")
            self.assertEqual(len(set(routed)), len(routed))
            hosts = [c["host"] for c in values["routing"]["cells"]]
            self.assertEqual(len(set(hosts)), len(hosts))
            for c in values["routing"]["cells"]:
                self.assertIn(f".{c['name']}.{env}.", c["host"])
            self.assertEqual(values["global"]["environment"], env)
            self.assertEqual(values["global"]["region"], region)

    def test_lifecycle_payloads_carry_no_card_number(self):
        self.assertIsNone(re.search(r"\d{13,19}", TOKEN))


if __name__ == "__main__":
    unittest.main()
