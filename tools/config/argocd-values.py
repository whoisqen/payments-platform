#!/usr/bin/env python3
"""Print the values of deploy/argocd from config/platform.yaml: helm template deploy/argocd -f <(tools/config/argocd-values.py)."""
import sys
from pathlib import Path
from urllib.parse import urlparse

import yaml

ROOT = Path(__file__).resolve().parents[2]


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
        },
    }


if __name__ == "__main__":
    cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
    sys.stdout.write(yaml.safe_dump(values(cfg), sort_keys=False))
