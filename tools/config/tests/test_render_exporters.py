import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import render_exporters  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = render_exporters.render(CFG)
BASE = render_exporters.OUT


def doc(path):
    return yaml.safe_load(OUT[path])


class RenderExportersTest(unittest.TestCase):
    def test_committed_files_are_current(self):
        for path, text in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), text, f"run tools/config/render_exporters.py: {path}")

    def test_secret_names_follow_prefix_environment_exporter(self):
        for name, secret in render_exporters.SECRETS.items():
            es = doc(BASE / name / "envs" / "stage" / "eu-central-1" / "externalsecret.yaml")
            self.assertEqual(es["spec"]["secretStoreRef"], {"kind": "ClusterSecretStore", "name": "aws-secrets-manager"})
            self.assertEqual(es["spec"]["target"]["name"], secret["name"])
            keys = {d["remoteRef"]["key"] for d in es["spec"]["data"]}
            self.assertEqual(keys, {f"{CFG['naming']['prefix']}/stage/exporters/{name}"})
            self.assertEqual([d["secretKey"] for d in es["spec"]["data"]], secret["keys"])

    def test_secret_names_match_the_values_the_charts_read(self):
        src = ROOT / "observability" / "exporters"
        pg = next(yaml.safe_load_all((src / "postgres.yaml").read_text()))
        self.assertEqual(pg["config"]["datasourceSecret"]["name"], render_exporters.SECRETS["postgres"]["name"])
        rd = next(yaml.safe_load_all((src / "redis.yaml").read_text()))
        self.assertEqual(rd["auth"]["secret"]["name"], render_exporters.SECRETS["redis"]["name"])
        overlay = yaml.safe_load((BASE / "redis" / "values.yaml").read_text())
        self.assertEqual(overlay["redisAddressConfig"]["source"]["name"], render_exporters.SECRETS["redis"]["name"])
        # the kafka exporter signs in to MSK with IAM through its pod identity: no connection secret
        self.assertNotIn("kafka", render_exporters.SECRETS)
        kf = next(yaml.safe_load_all((src / "kafka.yaml").read_text()))
        self.assertTrue(kf["sasl"]["awsiam"]["enabled"])
        self.assertTrue(kf["kafkaServer"][0].endswith(":9098"))

    def test_network_policy_denies_by_default_with_one_data_egress_and_monitoring_ingress(self):
        for name, (scrape, store) in render_exporters.PORTS.items():
            if not store:
                continue
            np = doc(BASE / name / "envs" / "dev" / "eu-central-1" / "networkpolicy.yaml")
            self.assertEqual(sorted(np["spec"]["policyTypes"]), ["Egress", "Ingress"])
            self.assertEqual(np["spec"]["ingress"][0]["from"][0]["namespaceSelector"]["matchLabels"]["kubernetes.io/metadata.name"], "monitoring")
            self.assertEqual(np["spec"]["ingress"][0]["ports"][0]["port"], scrape)
            data = [e for e in np["spec"]["egress"] if e["ports"][0]["port"] == store]
            self.assertEqual(len(data), 1)
            self.assertEqual([t["ipBlock"]["cidr"] for t in data[0]["to"]], CFG["deploy"]["dev"]["data_cidrs"])
            self.assertEqual(len(np["spec"]["egress"]), 2)

    def test_standby_region_uses_its_own_data_cidrs(self):
        np = doc(BASE / "postgres" / "envs" / "prod" / "us-east-1" / "networkpolicy.yaml")
        cidrs = [t["ipBlock"]["cidr"] for e in np["spec"]["egress"] for t in e["to"] if "ipBlock" in t]
        self.assertEqual(cidrs, CFG["deploy"]["prod"]["standby"]["us-east-1"]["data_cidrs"])

    def test_monitors_are_the_source_documents_with_the_kafka_port_fixed(self):
        kinds = {n: [d["kind"] for d in yaml.safe_load_all(OUT[BASE / n / "common" / "monitors.yaml"])] for n in ("postgres", "redis", "kafka", "clickhouse", "blackbox")}
        self.assertEqual(kinds["kafka"], ["ServiceMonitor", "PodMonitor"])
        self.assertEqual(kinds["blackbox"], ["Probe"] * 3)
        kafka = next(yaml.safe_load_all(OUT[BASE / "kafka" / "common" / "monitors.yaml"]))
        self.assertEqual(kafka["spec"]["endpoints"][0]["port"], "exporter-port")

    def test_no_secret_value_is_written(self):
        for path, text in OUT.items():
            self.assertNotRegex(text, r"://[^/\s]*:[^/\s@]+@", path)


if __name__ == "__main__":
    unittest.main()
