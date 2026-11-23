#!/usr/bin/env python3
"""Check config/platform.yaml: required keys, 12-digit account ids, CIDRs and the region list. Exit 1 on any error."""
import ipaddress
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {
    "owner": ["github_org", "github_repo", "contact_email", "cost_center_prefix"],
    "naming": ["prefix"],
    "registry": ["ecr_prefix", "ecr_repo_prefix"],
    "accounts": ["shared_services", "dev", "stage"],
    "regions": ["working", "recovery"],
    "dns": ["dev_zone", "stage_zone", "psp_domains", "grafana_url"],
    "storage": ["state_bucket_prefix"],
}
ACCOUNT = re.compile(r"^\d{12}$")
REGION = re.compile(r"^[a-z]{2}-[a-z]+-\d$")


def check(cfg):
    errors = []
    for section, keys in REQUIRED.items():
        block = cfg.get(section)
        if not isinstance(block, dict):
            errors.append(f"missing section `{section}`")
            continue
        for k in keys:
            if k not in block or block[k] in (None, ""):
                errors.append(f"`{section}.{k}` is empty")
    for name, acc in (cfg.get("accounts") or {}).items():
        if not ACCOUNT.match(str(acc)):
            errors.append(f"accounts.{name} must be a 12-digit id")
    regions = cfg.get("regions") or {}
    for r in [regions.get("working"), *(regions.get("recovery") or [])]:
        if not r or not REGION.match(str(r)):
            errors.append(f"region `{r}` is not a valid AWS region name")
    nets = {}
    for env, cidrs in (cfg.get("network") or {}).items():
        for region, cidr in cidrs.items():
            try:
                net = ipaddress.ip_network(cidr, strict=True)
            except ValueError:
                errors.append(f"network.{env}.{region} `{cidr}` is not a CIDR")
                continue
            for other_name, other in nets.items():
                if net.overlaps(other):
                    errors.append(f"network.{env}.{region} overlaps {other_name}")
            nets[f"network.{env}.{region}"] = net
    return errors


def main(argv=None):
    path = Path(argv[0]) if argv else ROOT / "config" / "platform.yaml"
    cfg = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    errors = check(cfg)
    for e in errors:
        print(f"config: error: {e}")
    print(f"config: {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
