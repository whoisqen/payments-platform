import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import REPO, dump, write  # noqa: E402

gen = REPO / "observability" / "slo" / "generated"
RECORDING = {
    "payments-authorization": ('http_server_requests_total{service="router",route="payments_confirm",code="500",fault="platform"}', 'http_server_requests_total{service="router",route="payments_confirm",code="200"}', "payments-authorization-availability", "availability", 0.001),
    "payments-webhooks": ('webhook_events_total{service="scheduler"}', None, "payments-webhooks-delivery", "delivery", None),
}
for path in sorted(gen.glob("*.yaml")):
    doc = yaml.safe_load(path.read_text())
    service = doc["metadata"]["name"][4:]
    tests = []
    for group in doc["spec"]["groups"]:
        for rule in group["rules"]:
            if "alert" not in rule:
                continue
            m = re.fullmatch(r"(slo:sli_error:ratio_rate(\w+))\{(.*?)\} > \((.*?)\) and (slo:sli_error:ratio_rate(\w+))\{.*?\} > \(.*?\)", rule["expr"])
            long_name, long_w, sel, thr, short_name, short_w = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5), m.group(6)
            threshold = eval(thr)
            ident = dict(re.findall(r'(\w+)="([^"]*)"', sel))
            base = {**ident, "team": rule["labels"]["team"], "owner": rule["labels"]["owner"], "layer": "application"}
            lab = ",".join(f'{k}="{v}"' for k, v in base.items())
            exp = {**rule["labels"], **ident}
            ann = rule["annotations"]
            fire_v, quiet_v = f"{threshold * 2:.6g}", f"{threshold * 0.1:.6g}"
            fire = {"eval_time": "10m", "alertname": rule["alert"], "exp_alerts": [{"exp_labels": exp, "exp_annotations": ann}]}
            quiet = {"eval_time": "10m", "alertname": rule["alert"], "exp_alerts": []}
            tests.append({"interval": "1m", "input_series": [{"series": f"{long_name}{{{lab}}}", "values": f"{fire_v}x15"}, {"series": f"{short_name}{{{lab}}}", "values": f"{fire_v}x15"}], "alert_rule_test": [fire]})
            tests.append({"interval": "1m", "input_series": [{"series": f"{long_name}{{{lab}}}", "values": f"{fire_v}x15"}, {"series": f"{short_name}{{{lab}}}", "values": f"{quiet_v}x15"}], "alert_rule_test": [quiet]})
    if service == "payments-authorization":
        err, ok, sid, slo, ratio = RECORDING[service]
        lab = {"sloth_id": sid, "sloth_service": service, "sloth_slo": slo, "team": "payments-core", "owner": "payments-core-oncall", "layer": "application"}
        tests.append({"interval": "1m", "input_series": [{"series": err, "values": "0+1x20"}, {"series": ok, "values": "0+999x20"}],
                      "promql_expr_test": [{"expr": f'slo:sli_error:ratio_rate5m{{sloth_id="{sid}"}}', "eval_time": "15m", "exp_samples": [{"labels": "slo:sli_error:ratio_rate5m{" + ",".join(f'{k}="{v}"' for k, v in lab.items()) + "}", "value": ratio}]}]})
    write(f"observability/tests/slo/{service}.test.yaml", dump({"rule_files": [f"../../slo/generated/{service}.yaml"], "evaluation_interval": "1m", "tests": tests}))
print("slo tests written")
