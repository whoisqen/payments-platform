import base64
import random
import re
import unittest
from pathlib import Path

import yaml

OTEL = Path(__file__).resolve().parents[1]
CONFIG = yaml.safe_load((OTEL / "collector.yaml").read_text())
SLOW = yaml.safe_load((OTEL.parent / "slo" / "config" / "slow-requests.yaml").read_text())
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unescape(text):
    return text.replace('\\"', '"').replace("\\\\", "\\")


def body_patterns():
    out = []
    for group in CONFIG["processors"]["transform/redact"]["log_statements"]:
        for stmt in group["statements"]:
            if stmt.startswith("replace_pattern(body"):
                out.append(re.compile(unescape(STRING.findall(stmt)[0])))
    return out


def blocked_values():
    return [re.compile(p) for p in CONFIG["processors"]["redaction"]["blocked_values"]]


def luhn_pan(rng, length=16, prefix="4"):
    digits = [int(c) for c in prefix] + [rng.randrange(10) for _ in range(length - len(prefix) - 1)]
    total = 0
    for i, d in enumerate(reversed(digits)):
        d = d * 2 if i % 2 == 0 else d
        total += d - 9 if d > 9 else d
    return "".join(map(str, digits)) + str((10 - total % 10) % 10)


def scrub(text):
    for pattern in body_patterns():
        text = pattern.sub("[REDACTED]", text)
    return text


class PanRedactionTest(unittest.TestCase):
    def setUp(self):
        self.rng = random.Random(7)

    def test_plain_spaced_and_dashed_pans_of_every_length(self):
        for length in (13, 15, 16, 19):
            pan = luhn_pan(self.rng, length)
            variants = [pan, " ".join(pan[i:i + 4] for i in range(0, len(pan), 4)), "-".join(pan[i:i + 4] for i in range(0, len(pan), 4))]
            for variant in variants:
                with self.subTest(length=length, variant=variant[:4] + "..."):
                    out = scrub(f"charge failed for card {variant} at psp")
                    self.assertNotIn(variant, out)
                    self.assertNotRegex(out, r"\d{4}")
                    self.assertTrue(any(p.search(variant) for p in blocked_values()), "the redaction processor misses it")

    def test_pan_in_json_and_query_string(self):
        pan = luhn_pan(self.rng, 16, "5")
        for text in (f'{{"card":"{pan}","amount":10}}', f"https://psp.example/pay?number={pan}&x=1"):
            self.assertNotIn(pan, scrub(text))

    def test_ordinary_values_survive(self):
        for text in ("payment created in 42 ms", "trace 4bf92f3577b34da6a3ce929d0e0e4736", "2026-11-22T10:15:30Z", "uuid 3f2b8c9e-1d4a-4c7b-9a55-0d6f1e2a7b10", "amount 12345 EUR"):
            self.assertEqual(scrub(text), text)

    def test_epoch_milliseconds_fail_closed(self):
        self.assertIn("[REDACTED]", scrub("ts 1732400000000"))


class SecretRedactionTest(unittest.TestCase):
    def test_tokens_keys_and_private_keys(self):
        jwt = ".".join(base64.urlsafe_b64encode(part).decode().rstrip("=") for part in (b'{"alg":"none"}', b'{"sub":"svc"}', b"signature-bytes"))
        samples = [
            "Authorization: Bearer " + "x" * 24,
            "Authorization: Basic " + base64.b64encode(b"svc:passw0rd-demo").decode(),
            "key " + "AKIA" + "Q" * 16,
            "jwt " + jwt,
            "-----BEGIN " + "RSA PRIVATE KEY-----",
            'password="' + "hunter" + '2"',
            "api_key=" + "k" * 20,
            "cvv: 123",
        ]
        for sample in samples:
            with self.subTest(sample=sample[:18]):
                out = scrub(sample)
                self.assertIn("[REDACTED]", out)
                self.assertNotIn("hunter", out)
                self.assertNotIn("Q" * 16, out)

    def test_secret_key_names_are_deleted(self):
        keys = {a["key"] for a in CONFIG["processors"]["attributes/drop-secret-keys"]["actions"] if a["action"] == "delete"}
        self.assertLessEqual({"authorization", "cookie", "card_number", "pan", "cvv", "cvc", "password", "x-api-key"}, keys)


class PipelineWiringTest(unittest.TestCase):
    def pipelines(self):
        return CONFIG["service"]["pipelines"]

    def test_every_component_in_a_pipeline_is_defined(self):
        defined = {k: set(CONFIG.get(k, {})) for k in ("receivers", "processors", "exporters", "connectors")}
        for name, p in self.pipelines().items():
            for kind in ("receivers", "processors", "exporters"):
                for comp in p[kind]:
                    self.assertTrue(comp in defined[kind] or comp in defined["connectors"], f"{name}: {comp}")

    def test_shipping_pipelines_redact_before_any_exporter(self):
        for name in ("logs/ship", "traces", "metrics", "metrics/spanmetrics"):
            procs = self.pipelines()[name]["processors"]
            self.assertEqual(procs[0], "memory_limiter", name)
            self.assertIn("redaction", procs, name)
            if name != "metrics/spanmetrics":
                self.assertIn("attributes/drop-secret-keys", procs, name)
                self.assertLess(procs.index("attributes/drop-secret-keys"), procs.index("redaction"))
        for name in ("logs/ship", "metrics", "metrics/spanmetrics", "traces/sampling"):
            self.assertEqual(self.pipelines()[name]["processors"][-1], "batch", name)
        for name in ("logs/ship", "traces"):
            self.assertIn("transform/redact", self.pipelines()[name]["processors"])
        for name in ("metrics", "metrics/spanmetrics"):
            self.assertIn("transform/metric-labels", self.pipelines()[name]["processors"])

    def test_traces_leave_only_through_the_redacting_pipeline(self):
        p = self.pipelines()
        self.assertEqual(p["traces"]["receivers"], ["otlp"])
        self.assertEqual(p["traces"]["exporters"], ["forward/traces"])
        self.assertLess(p["traces"]["processors"].index("redaction"), p["traces"]["processors"].index("transform/slow"))
        fed = [name for name, pl in p.items() if "forward/traces" in pl["receivers"]]
        self.assertEqual(sorted(fed), ["traces/sampling", "traces/spanmetrics"])
        for name in fed:
            self.assertNotIn("otlp", p[name]["receivers"], name)
        self.assertEqual(p["traces/sampling"]["exporters"], ["otlp/central-traces"])
        self.assertEqual(p["traces/spanmetrics"]["exporters"], ["span_metrics/slow"])
        self.assertEqual(p["metrics/spanmetrics"]["receivers"], ["span_metrics/slow"])

    def test_pan_detection_runs_on_raw_logs_and_never_exports_them(self):
        detect = self.pipelines()["logs/detect"]
        self.assertEqual(detect["exporters"], ["count/pan"])
        self.assertEqual(detect["processors"], ["memory_limiter"])
        self.assertIn("count/pan", self.pipelines()["metrics"]["receivers"])

    def test_forbidden_metric_labels_are_stripped(self):
        stmt = CONFIG["processors"]["transform/metric-labels"]["metric_statements"][0]["statements"][0]
        pattern = re.compile(unescape(STRING.findall(stmt)[0]))
        for label in ("payment_id", "customer_id", "merchant_id", "idempotency_key", "card_number", "pan", "cvv", "token"):
            self.assertRegex(label, pattern)
        self.assertNotRegex("psp", pattern)

    def test_tail_sampling_follows_section_7(self):
        policies = {p["name"]: p for p in CONFIG["processors"]["tail_sampling"]["policies"]}
        self.assertEqual(policies["rest"]["probabilistic"]["sampling_percentage"], 2)
        self.assertEqual(policies["errors"]["status_code"]["status_codes"], ["ERROR"])
        self.assertFalse([p for p in policies.values() if p["type"] == "latency"], "a global latency policy keeps every PSP-bound request")

    def test_no_literal_secret_or_credentialed_url_in_the_config(self):
        text = (OTEL / "collector.yaml").read_text()
        self.assertNotRegex(text, r"https?://[^/\s]*:[^/\s@]*@")
        for line in text.splitlines():
            if re.search(r"(token|password|api_key|secret)\s*:\s*\S", line, re.I) and "action" not in line and "key:" not in line:
                self.assertIn("${env:", line)

    def test_transport_uses_tls_with_client_certificates(self):
        for name, exp in CONFIG["exporters"].items():
            self.assertIn("cert_file", exp["tls"], name)
        for proto in CONFIG["receivers"]["otlp"]["protocols"].values():
            self.assertIn("client_ca_file", proto["tls"])


def total_ms(spec):
    return spec["threshold_ms"] + (SLOW["psp_allowance_ms"] if spec["measure"] == "own" else 0)


def other_routes():
    base = SLOW["other"]["threshold_ms"]
    return {route: max(base, ms) for route, ms in (SLOW["other"]["routes"] or {}).items()}


class SlowRequestTest(unittest.TestCase):
    def policies(self):
        return {p["name"]: p for p in CONFIG["processors"]["tail_sampling"]["policies"]}

    def statements(self):
        groups = CONFIG["processors"]["transform/slow"]["trace_statements"]
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["conditions"], ['kind == SPAN_KIND_SERVER and attributes["http.route"] != nil'])
        return groups[0]["statements"]

    def test_every_request_type_has_a_policy_with_the_yaml_thresholds(self):
        policies = self.policies()
        for name, spec in SLOW["types"].items():
            with self.subTest(type=name):
                subs = {s["type"]: s for s in policies[f"slow-{name}"]["and"]["and_sub_policy"]}
                self.assertEqual(set(subs), {"string_attribute", "latency"})
                attrs = [s for s in policies[f"slow-{name}"]["and"]["and_sub_policy"] if s["type"] == "string_attribute"]
                by_key = {s["string_attribute"]["key"]: s["string_attribute"] for s in attrs}
                self.assertEqual(by_key["http.route"]["values"], spec["routes"])
                self.assertEqual(by_key["http.method"]["values"], [spec["method"]])
                self.assertFalse(any(s.get("invert_match") for s in by_key.values()))
                self.assertEqual(subs["latency"]["latency"]["threshold_ms"], total_ms(spec))
        other = policies["slow-other"]["ottl_condition"]["span"]
        self.assertEqual(other, ['attributes["request.type"] == "other" and attributes["slow"] == true'])

    def test_the_mark_uses_the_yaml_thresholds(self):
        text = "\n".join(self.statements())
        for name, spec in SLOW["types"].items():
            with self.subTest(type=name):
                routes = " or ".join(f'attributes["http.route"] == "{r}"' for r in spec["routes"])
                routes = f"({routes})" if len(spec["routes"]) > 1 else routes
                self.assertIn(f'set(attributes["request.type"], "{name}") where attributes["http.method"] == "{spec["method"]}" and {routes}', text)
                self.assertIn(f'set(attributes["slow"], true) where attributes["request.type"] == "{name}" and end_time_unix_nano - start_time_unix_nano > {total_ms(spec) * 1000000}', text)
        excluded = "".join(f' and attributes["http.route"] != "{route}"' for route in other_routes())
        generic = f'set(attributes["slow"], true) where attributes["request.type"] == "other"{excluded} and end_time_unix_nano - start_time_unix_nano > {SLOW["other"]["threshold_ms"] * 1000000}'
        self.assertIn(generic, self.statements(), "an override route must not be marked by the generic threshold")
        for route, ms in other_routes().items():
            self.assertIn(f'set(attributes["slow"], true) where attributes["request.type"] == "other" and attributes["http.route"] == "{route}" '
                          f'and end_time_unix_nano - start_time_unix_nano > {ms * 1000000}', self.statements())
        self.assertEqual(self.statements()[0], 'set(attributes["request.type"], "other")', "the default type must be set before the specific ones")
        marks = [s for s in self.statements() if s.startswith('set(attributes["slow"]')]
        self.assertEqual(len(marks), len(SLOW["types"]) + 1 + len(other_routes()))

    def test_status_reads_are_told_apart_from_updates_on_the_same_route(self):
        self.assertEqual(SLOW["types"]["status"]["method"], "GET")
        self.assertIn("/payments/{payment_id}", SLOW["types"]["status"]["routes"])

    def test_slow_metrics_have_only_bounded_labels(self):
        conn = CONFIG["connectors"]["span_metrics/slow"]
        self.assertEqual([d["name"] for d in conn["dimensions"]], ["http.route", "cell", "slow"])
        self.assertEqual(set(conn["exclude_dimensions"]), {"span.name", "span.kind", "status.code"})
        self.assertTrue(conn["exemplars"]["enabled"])
        self.assertEqual(conn["histogram"]["unit"], "s")
        self.assertEqual(conn["aggregation_temporality"], "AGGREGATION_TEMPORALITY_CUMULATIVE")
        stmts = [s for g in CONFIG["processors"]["transform/spanmetrics-labels"]["metric_statements"] for s in g["statements"]]
        self.assertIn('keep_keys(attributes, ["service.name"])', stmts)
        self.assertIn('delete_key(attributes, "service.name")', stmts)

    def test_psp_types_include_the_allowance_and_buckets_cover_every_threshold(self):
        bounds = []
        for b in CONFIG["connectors"]["span_metrics/slow"]["histogram"]["explicit"]["buckets"]:
            bounds.append(int(b[:-2]) if b.endswith("ms") else int(float(b[:-1]) * 1000))
        for name, spec in SLOW["types"].items():
            self.assertIn(total_ms(spec), bounds, name)
            if spec["measure"] == "own":
                self.assertGreater(total_ms(spec), spec["threshold_ms"])
        self.assertIn(SLOW["other"]["threshold_ms"], bounds)

    def test_only_routed_server_spans_feed_the_metrics(self):
        self.assertEqual(CONFIG["processors"]["filter/route-spans"]["traces"]["span"], ['kind != SPAN_KIND_SERVER or attributes["http.route"] == nil'])
        self.assertEqual(CONFIG["service"]["pipelines"]["traces/spanmetrics"]["processors"], ["filter/route-spans"])

    def test_cell_comes_from_the_pod_label(self):
        labels = CONFIG["processors"]["k8sattributes/cell"]["extract"]["labels"]
        self.assertIn({"tag_name": "cell", "key": "payments-platform/cell", "from": "pod"}, labels)


if __name__ == "__main__":
    unittest.main()
