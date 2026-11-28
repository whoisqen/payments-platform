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
    "accounts": ["management", "log_archive", "audit", "shared_services", "dev", "stage", "prod"],
    "regions": ["working", "recovery"],
    "dns": ["dev_zone", "stage_zone", "prod_zone", "psp_domains", "grafana_url", "admin_zone"],
    "storage": ["state_bucket_prefix"],
    "runners": ["version", "sha256"],
    "central": ["metrics_remote_write_url", "alertmanager_url", "sentry_url", "logs_otlp_endpoint", "traces_otlp_endpoint", "dedup_interval", "ingest_client_ca"],
}
STANDBY_ENVS = ("prod",)  # only prod has a standby region
GRAFANA_GROUPS = ("admin", "sre", "security", "engineering", "finance", "audit")
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
    for env in STANDBY_ENVS:
        endpoints = ((cfg.get("deploy") or {}).get(env) or {}).get("ingress_endpoints")
        wanted = {regions.get("working"), *(regions.get("recovery") or [])[:1]}
        if not isinstance(endpoints, dict) or not wanted <= set(endpoints):
            errors.append(f"`deploy.{env}.ingress_endpoints` needs an ingress host for the working region and the standby region")
    access = cfg.get("access") or {}
    if not re.match(r"^[a-z0-9.-]+\.(okta|oktapreview|okta-emea)\.com$", str(access.get("okta_domain", ""))):
        errors.append("`access.okta_domain` must be the host name of an Okta organization, without https://")
    admins = access.get("admin_user_ids") or []
    if len(admins) == 1:
        errors.append("`access.admin_user_ids` needs at least two administrators, or none")
    groups = access.get("grafana_groups") or {}
    for role in GRAFANA_GROUPS:
        if not re.match(r"^[a-z0-9][a-z0-9._-]*$", str(groups.get(role, ""))):
            errors.append(f"`access.grafana_groups.{role}` must be a group name of the identity provider")
    if len(set(groups.values())) != len(groups):
        errors.append("`access.grafana_groups` must name a different group for every role")
    central = cfg.get("central") or {}
    for key in ("metrics_remote_write_url", "alertmanager_url", "sentry_url"):
        if central.get(key) and not str(central[key]).startswith("https://"):
            errors.append(f"`central.{key}` must be an https:// URL")
    domain = str((central.get("opensearch") or {}).get("domain_name", ""))
    # Amazon OpenSearch Service: 3 to 28 characters, lower-case letter first, then lower-case letters, digits and hyphens
    if not re.match(r"^[a-z][a-z0-9-]{2,27}$", domain):
        errors.append("`central.opensearch.domain_name` must be 3 to 28 lower-case letters, digits or hyphens, starting with a letter")
    if not str(central.get("sentry_slack_channel", "")).startswith("#"):
        errors.append("`central.sentry_slack_channel` must be a Slack channel name starting with #")
    if not re.match(r"^(REPLACE_[A-Z_]+|[A-Z0-9]{9,12})$", str(central.get("sentry_slack_workspace_id", ""))):
        errors.append("`central.sentry_slack_workspace_id` must be the Slack workspace id (for example T0123ABCD)")
    if central.get("dedup_interval") and not re.match(r"^[0-9]+(s|m)$", str(central["dedup_interval"])):
        errors.append("`central.dedup_interval` must look like 30s")
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


CLASS = re.compile(r"^db\.[a-z0-9]+\.[a-z0-9]+$")
SECTIONS = {"aurora", "memorydb", "standby", "eks", "protection"}


def check_sizing(reference, own, env):
    """Rules of config/environments: prod defines every section, the others override keys that exist there; cde is never Spot."""
    errors = []
    for name, doc in (("prod", reference), (env, own)):
        if not isinstance(doc, dict):
            errors.append(f"config/environments/{name}.yaml is not a mapping")
            return errors
    missing = SECTIONS - set(reference)
    if missing:
        errors.append(f"config/environments/prod.yaml lacks sections {sorted(missing)}")
    for section, keys in own.items():
        if section not in reference:
            errors.append(f"config/environments/{env}.yaml: unknown section `{section}`")
        elif not isinstance(keys, dict) or set(keys) - set(reference[section]):
            errors.append(f"config/environments/{env}.yaml: `{section}` may only set keys of prod.yaml, got {sorted(set(keys) - set(reference[section])) if isinstance(keys, dict) else keys}")
    merged = {k: {**v, **own.get(k, {})} for k, v in reference.items() if isinstance(v, dict)}
    for key in ("writer_class", "reader_class"):
        if not CLASS.match(str(merged.get("aurora", {}).get(key, ""))):
            errors.append(f"{env}: aurora.{key} must look like db.r7g.large")
    if not CLASS.match(str(merged.get("memorydb", {}).get("node_type", ""))):
        errors.append(f"{env}: memorydb.node_type must look like db.r7g.large")
    spot = merged.get("eks", {}).get("spot_pools", [])
    if "cde" in spot or set(spot) - {"payments", "stateful", "workers"}:
        errors.append(f"{env}: eks.spot_pools may hold payments, stateful and workers only; CDE nodes are never Spot")
    standby = merged.get("standby", {})
    # A pilot light (compute_enabled false) keeps headless secondaries; only a standing warm standby needs readers
    if standby.get("enabled") and standby.get("compute_enabled", True) and not standby.get("reader_count", 0):
        errors.append(f"{env}: a warm standby needs standby.reader_count of at least 1")
    return errors


def main(argv=None):
    path = Path(argv[0]) if argv else ROOT / "config" / "platform.yaml"
    cfg = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    errors = check(cfg)
    if not argv:
        envdir = ROOT / "config" / "environments"
        reference = yaml.safe_load((envdir / "prod.yaml").read_text(encoding="utf-8")) or {}
        for env in ("dev", "stage", "prod"):
            own = yaml.safe_load((envdir / f"{env}.yaml").read_text(encoding="utf-8")) or {}
            errors += check_sizing(reference, own, env)
    for e in errors:
        print(f"config: error: {e}")
    print(f"config: {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
