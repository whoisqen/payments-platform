import base64
import random
import re
import unittest
from pathlib import Path

import yaml

OTEL = Path(__file__).resolve().parents[1]
CONFIG = yaml.safe_load((OTEL / "collector.yaml").read_text())
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
        for name in ("logs/ship", "traces", "metrics"):
            procs = self.pipelines()[name]["processors"]
            self.assertEqual(procs[0], "memory_limiter", name)
            self.assertIn("redaction", procs, name)
            self.assertIn("attributes/drop-secret-keys", procs, name)
            self.assertLess(procs.index("attributes/drop-secret-keys"), procs.index("redaction"))
            self.assertEqual(procs[-1], "batch", name)
        for name in ("logs/ship", "traces"):
            self.assertIn("transform/redact", self.pipelines()[name]["processors"])
        self.assertIn("transform/metric-labels", self.pipelines()["metrics"]["processors"])

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
        self.assertEqual(policies["slow"]["latency"]["threshold_ms"], 300)
        self.assertEqual(policies["rest"]["probabilistic"]["sampling_percentage"], 2)
        self.assertEqual(policies["errors"]["status_code"]["status_codes"], ["ERROR"])

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


if __name__ == "__main__":
    unittest.main()
