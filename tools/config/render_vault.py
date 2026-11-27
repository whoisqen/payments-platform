#!/usr/bin/env python3
"""Write the per-environment values of the Vault and External Secrets add-ons from config/platform.yaml.

One Vault serves every environment from the central cluster of shared-services:
  deploy/platform/vault/envs/shared-services/<region>.yaml          values of the upstream vault chart
  deploy/platform/vault/envs/shared-services/<region>.config.yaml   values of the vault-config chart, with the cluster list
Per environment and region of the clusters (selected by the cluster labels payments-platform/environment and /region):
  deploy/platform/external-secrets/envs/<env>/<region>.yaml  values of the external-secrets-config chart
Names follow <prefix>-<env>-<region short>-<component>; roles come from EKS Pod Identity associations (Terraform), so no role ARN is written.
The one value left to CI is the snapshot image digest (deploy/envs/<env>/images.yaml, key vault-snapshot).

Usage: render_vault.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
"""
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent / "render"))
import clusters  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
VAULT_PORT = 443  # the internal admin gateway of shared-services terminates TLS for vault.<admin zone>


def short(region):
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


def environments(cfg):
    """Environment -> regions of the clusters that read Vault: the working region, plus us-east-1 where the environment has its standby."""
    out = {}
    for c in clusters.clusters(cfg):
        if c["environment"] in ("dev", "stage", "prod"):
            out.setdefault(c["environment"], [])
            if c["region"] not in out[c["environment"]]:
                out[c["environment"]].append(c["region"])
    return {e: sorted(r, key=lambda x: x != cfg["regions"]["working"]) for e, r in out.items()}


def cidrs(items, indent):
    return "".join(f"{' ' * indent}- {i}\n" for i in items)


def endpoint_cidrs(cfg, env, region):
    d = cfg["deploy"][env]
    if region == cfg["regions"]["working"]:
        return d["endpoint_cidrs"]
    return d["standby"][region]["endpoint_cidrs"]


def render(cfg):
    """One Vault in shared-services (central cluster) serves every environment; every other cluster reads it through its own jwt mount."""
    p, reg = cfg["naming"]["prefix"], cfg["registry"]
    repo = f"{reg['ecr_prefix']}/{reg['ecr_repo_prefix']}/vault-snapshot"
    working = cfg["regions"]["working"]
    ss_vpc = cfg["network"]["shared_services"][working]
    host = cfg["vault"]["host"]
    name = f"{p}-shared-services-{short(working)}"
    envs = environments(cfg)
    client_vpcs = [cfg["network"][e][r] for e, regions in envs.items() for r in regions]
    remote = [c for c in clusters.clusters(cfg) if c["environment"] != "shared-services"]
    files = {}
    files[f"vault/envs/shared-services/{working}.yaml"] = f"""# shared-services {working}: the one Vault of the platform (central cluster); unseal key and region of the servers, the pod role comes from the Pod Identity association vault/vault
server:
  extraEnvironmentVars:
    AWS_REGION: {working}
    VAULT_AWSKMS_SEAL_KEY_ID: alias/{name}-vault-unseal
"""
    cl = "".join(f"    - {{name: {c['name']}, environment: {c['environment']}, component: {c['component']}, kind: {clusters.kind(c['component'])}}}\n" for c in remote)
    files[f"vault/envs/shared-services/{working}.config.yaml"] = f"""# shared-services {working}: names Terraform creates; pod roles come from Pod Identity associations vault/vault-snapshot and vault/vault-bootstrap
requireResolved: true

snapshot:
  image:
    repository: {repo}
  bucket: {name}-vault-snapshots
  region: {working}

bootstrap:
  region: {working}
  initSecretId: {p}/shared-services/vault/init
  workloads:
    # Every cluster of infra/live (tools/config/clusters.py): one jwt auth mount k8s-<name>, configured from <prefix>/argocd/clusters/<name>
    registrationPrefix: {p}/argocd/clusters/
    environments: [{", ".join(envs)}]
    clusters:
{cl}
networkPolicy:
  # The clusters of every environment reach Vault through the transit gateway
  clientCidrs:
{cidrs(client_vpcs, 4)}  awsEndpointCidrs:
    - {ss_vpc}
"""
    bundle = (cfg.get("vault") or {}).get("ca_bundle")
    ca = f"  caBundle: {bundle}\n" if bundle else ""
    for env, regions in envs.items():
        for region in regions:
            ep = cidrs(endpoint_cidrs(cfg, env, region), 4)
            files[f"external-secrets/envs/{env}/{region}.yaml"] = f"""# {env} {region}: the pod role comes from the Pod Identity association external-secrets/external-secrets
requireResolved: true

awsSecretsManager:
  region: {region}

vault:
  # The one Vault in shared-services; the auth mount is k8s-<cluster name>, set per cluster by the add-on
  server: https://{host}:{VAULT_PORT}
{ca}
networkPolicy:
  awsEndpointCidrs:
{ep}  vaultCidrs:
    - {ss_vpc}
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
