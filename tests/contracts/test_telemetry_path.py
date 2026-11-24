import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from contracts import model  # noqa: E402

CHARTS = model.CHARTS
COLLECTOR = yaml.safe_load((model.DEPLOY / "platform" / "otel-collector" / "values.yaml").read_text(encoding="utf-8"))
ENDPOINT = f"http://{COLLECTOR['fullnameOverride']}.monitoring.svc.cluster.local:4317"


def load(chart):
    return yaml.safe_load((CHARTS / chart / "values.yaml").read_text(encoding="utf-8"))


def containers():
    router, drainer, scheduler = load("router"), load("drainer"), load("scheduler")
    yield "router", router["container"]["env"], router["networkPolicy"], "ROUTER"
    yield "drainer", drainer["container"]["env"], drainer["networkPolicy"], "DRAINER"
    for part in ("producer", "consumer"):
        yield f"scheduler {part}", scheduler[part]["container"]["env"], scheduler[part]["networkPolicy"], "ROUTER"


class TelemetryPath(unittest.TestCase):
    def test_every_service_sends_traces_and_metrics_to_the_collector_service(self):
        for name, env, _, prefix in containers():
            with self.subTest(service=name):
                self.assertEqual(env[f"{prefix}__LOG__TELEMETRY__TRACES_ENABLED"], "true")
                self.assertEqual(env[f"{prefix}__LOG__TELEMETRY__METRICS_ENABLED"], "true")
                self.assertEqual(env[f"{prefix}__LOG__TELEMETRY__OTEL_EXPORTER_OTLP_ENDPOINT"], ENDPOINT)

    def test_every_service_may_reach_the_collector_and_nothing_else_is_added(self):
        for name, _, policy, _ in containers():
            with self.subTest(service=name):
                rules = policy["extraEgress"]
                self.assertEqual(len(rules), 1)
                selector = rules[0]["to"][0]
                self.assertEqual(selector["namespaceSelector"]["matchLabels"]["kubernetes.io/metadata.name"], "monitoring")
                self.assertEqual(selector["podSelector"]["matchLabels"]["app.kubernetes.io/name"], "opentelemetry-collector")
                self.assertEqual([p["port"] for p in rules[0]["ports"]], [4317])

    def test_the_collector_accepts_the_namespaces_of_the_services(self):
        policy = yaml.safe_load((model.DEPLOY / "platform" / "otel-collector" / "manifests" / "networkpolicy.yaml").read_text(encoding="utf-8"))
        allowed = set(policy["spec"]["ingress"][0]["from"][0]["namespaceSelector"]["matchExpressions"][0]["values"])
        self.assertTrue({"payments", "payments-edge", "control-center"} <= allowed)


if __name__ == "__main__":
    unittest.main()
