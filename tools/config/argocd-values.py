#!/usr/bin/env python3
"""Print the values of deploy/argocd from config/platform.yaml: helm template deploy/argocd -f <(tools/config/argocd-values.py)."""
import sys
from pathlib import Path
from urllib.parse import urlparse

import yaml

ROOT = Path(__file__).resolve().parents[2]


def sizing(env):
    ref = yaml.safe_load((ROOT / "config" / "environments" / "prod.yaml").read_text(encoding="utf-8"))
    own_path = ROOT / "config" / "environments" / f"{env}.yaml"
    own = (yaml.safe_load(own_path.read_text(encoding="utf-8")) or {}) if own_path.exists() else {}
    # The same one-level merge as infra/live/<env>/env.hcl
    return {k: {**v, **own.get(k, {})} for k, v in ref.items()}


def pilot_light(cfg):
    # A recovery region whose clusters the failover builds has no cluster to sync to until then
    out = []
    for f in sorted((ROOT / "config" / "environments").glob("*.yaml")):
        s = sizing(f.stem).get("standby", {})
        if s.get("enabled") and not s.get("compute_enabled", False):
            out.append({"environment": f.stem, "region": cfg["regions"]["recovery"][0]})
    return out


def values(cfg):
    org, repo = cfg["owner"]["github_org"], cfg["owner"]["github_repo"]
    working = cfg["regions"]["working"]
    return {
        "repo": {"url": f"https://github.com/{org}/{repo}", "revision": "main"},
        "cluster": {"namePrefix": cfg["storage"]["state_bucket_prefix"], "region": working},
        "observability": {"grafanaUrl": cfg["dns"]["grafana_url"]},
        "central": {
            "metricsRemoteWriteUrl": cfg["central"]["metrics_remote_write_url"],
            "alertmanagerHost": urlparse(cfg["central"]["alertmanager_url"]).netloc,
            "sentryUrl": cfg["central"]["sentry_url"],
            "dedupInterval": cfg["central"]["dedup_interval"],
            "logsOtlpEndpoint": cfg["central"]["logs_otlp_endpoint"],
            "tracesOtlpEndpoint": cfg["central"]["traces_otlp_endpoint"],
        },
        "pilotLight": pilot_light(cfg),
    }


if __name__ == "__main__":
    cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
    sys.stdout.write(yaml.safe_dump(values(cfg), sort_keys=False))
