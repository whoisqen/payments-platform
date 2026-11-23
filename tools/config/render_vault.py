#!/usr/bin/env python3
"""Write the per-environment values of the Vault and External Secrets add-ons from config/platform.yaml.

Files per environment and region (selected by the cluster labels payments-platform/environment and /region):
  deploy/platform/vault/envs/<env>/<region>.yaml          values of the upstream vault chart
  deploy/platform/vault/envs/<env>/<region>.config.yaml   values of the vault-config chart
  deploy/platform/external-secrets/envs/<env>/<region>.yaml  values of the external-secrets-config chart
Names follow <prefix>-<env>-<region short>-<component>; roles come from EKS Pod Identity associations (Terraform), so no role ARN is written.
The one value left to CI is the snapshot image digest (deploy/envs/<env>/images.yaml, key vault-snapshot).

Usage: render_vault.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
VAULT_PORT = 8200


def short(region):
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


def environments(cfg):
    """Environment -> regions: the working region, plus the standby region where the environment has one."""
    work, recovery = cfg["regions"]["working"], cfg["regions"]["recovery"]
    out = {}
    for env in ("dev", "stage", "prod"):
        # prod appears only once config/platform.yaml carries its account and zone
        if env not in cfg["accounts"] or f"{env}_zone" not in cfg["dns"]:
            continue
        standby = list((cfg.get("deploy", {}).get(env, {}).get("standby") or {}))
        if env == "prod" and not standby:
            standby = recovery[:1]
        out[env] = [work] + standby
    return out


def cidrs(items, indent):
    return "".join(f"{' ' * indent}- {i}\n" for i in items)


def endpoint_cidrs(cfg, env, region):
    d = cfg["deploy"][env]
    if region == cfg["regions"]["working"]:
        return d["endpoint_cidrs"]
    return d["standby"][region]["endpoint_cidrs"]


def render(cfg):
    p, reg = cfg["naming"]["prefix"], cfg["registry"]
    repo = f"{reg['ecr_prefix']}/{reg['ecr_repo_prefix']}/vault-snapshot"
    files = {}
    for env, regions in environments(cfg).items():
        zone = cfg["dns"][f"{env}_zone"]
        for region in regions:
            name = f"{p}-{env}-{short(region)}"
            ep = cidrs(endpoint_cidrs(cfg, env, region), 4)
            vpc = cfg["network"][env][region]
            files[f"vault/envs/{env}/{region}.yaml"] = f"""# {env} {region}: unseal key and region of the Vault servers; the pod role comes from the Pod Identity association vault/vault
server:
  extraEnvironmentVars:
    AWS_REGION: {region}
    VAULT_AWSKMS_SEAL_KEY_ID: alias/{name}-vault-unseal
"""
            files[f"vault/envs/{env}/{region}.config.yaml"] = f"""# {env} {region}: names Terraform creates; pod roles come from Pod Identity associations vault/vault-snapshot and vault/vault-bootstrap
requireResolved: true

snapshot:
  image:
    repository: {repo}
  bucket: {name}-vault-snapshots
  region: {region}

bootstrap:
  region: {region}
  initSecretId: {p}/{env}/vault/init

networkPolicy:
  # Other clusters of the VPC call Vault through its load balancer
  clientCidrs:
    - {vpc}
  awsEndpointCidrs:
{ep}"""
            files[f"external-secrets/envs/{env}/{region}.yaml"] = f"""# {env} {region}: the pod role comes from the Pod Identity association external-secrets/external-secrets
requireResolved: true

awsSecretsManager:
  region: {region}

vault:
  server: https://vault.{zone}:{VAULT_PORT}

networkPolicy:
  awsEndpointCidrs:
{ep}  vaultCidrs:
    - {vpc}
"""
    return {ROOT / "deploy" / "platform" / k: v for k, v in files.items()}


def main(argv):
    cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
    check = "--check" in argv
    changed = []
    for path, text in render(cfg).items():
        old = path.read_text(encoding="utf-8") if path.exists() else None
        if old != text:
            changed.append(path.relative_to(ROOT).as_posix())
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    verb = "would change" if check else "updated"
    for c in changed:
        print(f"render-vault: {verb} {c}")
    print(f"render-vault: {len(changed)} file(s) {verb}")
    return 1 if changed and check else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
