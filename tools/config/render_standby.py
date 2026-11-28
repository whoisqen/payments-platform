#!/usr/bin/env python3
"""Write deploy/envs/<env>/<standby region>/** from config/platform.yaml and the working region's cell list.

Usage: render_standby.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
ENVS = {"prod": "production"}  # environment -> RUN_ENV of its workloads; only prod has a standby region


def short(region):
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


def lines(items, indent):
    return "".join(f"{' ' * indent}- {i}\n" for i in items)


def render(cfg, env):
    ENV, RUN_ENV = env, ENVS[env]
    prefix = cfg["storage"]["state_bucket_prefix"]
    d = cfg["deploy"][ENV]
    work, standby = cfg["regions"]["working"], cfg["regions"]["recovery"][0]
    s = short(standby)
    cidrs = d["standby"][standby]
    host = lambda region, kind, name, suffix, tail="": f"{prefix}-{ENV}-{short(region)}-{kind}-{name}{suffix}{tail}"
    # The cluster endpoint of the local global-database secondary: read-only until promotion, then the writer; only the migrations Job uses it
    writer = lambda name: f"{host(standby, 'aurora', name, '')}.cluster-{d['rds_suffix']}.{standby}.rds.amazonaws.com"
    # The RDS Proxy of the secondary (aurora-global output proxy_endpoint); it follows the cluster through promotion
    proxy = lambda name: f"{host(standby, 'aurora', name, '')}.proxy-{d['rds_suffix']}.{standby}.rds.amazonaws.com"
    redis = lambda name: f"clustercfg.{prefix}-{ENV}-{s}-memorydb-{name}.{d['memorydb_suffix']}.memorydb.{standby}.amazonaws.com"
    base = ROOT / "deploy" / "envs" / ENV
    cells = sorted(p.name for p in (base / work).iterdir() if p.name.startswith("cell-") or p.name == "spare")
    files = {}
    files[f"{standby}/values.yaml"] = (
        "# Hot standby: the same Applications run here at full size against the local replicas; promotion changes no values\n"
        f"global:\n  region: {standby}\n  dataCidrs:\n{lines(cidrs['data_cidrs'], 4)}  endpointCidrs:\n{lines(cidrs['endpoint_cidrs'], 4)}")
    for c in cells:
        r_redis = redis(c)
        # The spare keeps three pods of each workload, like the working region's spare
        floor = lambda indent: f"{' ' * indent}autoscaling:\n{' ' * indent}  minReplicas: 3\n" if c == "spare" else ""
        router = "router:\n" + floor(2) + "\n" if c == "spare" else ""
        # Tenant, users (<cell>-<service>), locker host and the rest of global.hyperswitch come from envs/<env>/values.yaml, shared with the working region
        files[f"{standby}/{c}/values.yaml"] = f"""# Cell {c} in the standby region: local Aurora secondary (through RDS Proxy) and MemoryDB, ready to become the writer on promotion; endpoints are placeholders until infra/live exports them
global:
  cell: {c}
  hyperswitch:
    database:
      # aurora-global output proxy_endpoint; the proxy has no read-only endpoint, so replica reads use it too
      host: {proxy(c)}
    redis:
      host: {r_redis}
    kms:
      # Cell key of the kms-set stack in this region
      keyAlias: alias/{prefix}-{ENV}-{s}-{c}
      region: {standby}

# Migrations run only where the writer is; enable after promotion
migrations:
  enabled: false
  database:
    host: {writer(c)}

{router}drainer:
{floor(2)}  container:
    env:
      REDIS_ADDRESS: {r_redis}:6379

scheduler:
  consumer:
    container:
      env:
        REDIS_ADDRESS: {r_redis}:6379
{floor(4)}"""
    files[f"{standby}/locker/values.yaml"] = f"""# Locker of the standby region; its database is the local global-database secondary
global:
  environment: {ENV}
  region: {standby}
  dataCidrs:
{lines(cidrs['data_cidrs'], 4)}  endpointCidrs:
{lines(cidrs['endpoint_cidrs'], 4)}
locker:
  container:
    env:
      RUN_ENV: {RUN_ENV}
  # The proxy endpoint is a placeholder until the aurora stack outputs it; the KMS alias is the locker key of this region
  config:
    database:
      host: {host(standby, 'aurora', 'locker', '')}.proxy-{d['rds_suffix']}.{standby}.rds.amazonaws.com
    secrets_management:
      aws_kms:
        key_id: alias/{prefix}-{ENV}-{s}-locker
        region: {standby}

# Migrations run only where the writer is; enable after promotion
locker-migrations:
  enabled: false
  database:
    host: {writer('locker')}
    name: locker
"""
    edge = "".join(f"    - name: {c}\n      host: router.payments.svc.{c}.{d['cluster_domain']}\n" for c in cells)
    files[f"{standby}/edge/values.yaml"] = f"""# Edge routing; one file holds everything because this release has no cell layer
global:
  environment: {ENV}
  region: {standby}

gateway:
  hosts:
    - {d['gateway_host']}

# Client certificate of the edge for the router gateways of the cells, from the central Vault (vault.host of config/platform.yaml)
edgeClient:
  pki:
    vaultServer: https://{cfg['vault']['host']}

routing:
  cells:
{edge}"""
    return {base / k: v for k, v in files.items()}


def main(argv):
    cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
    changed = []
    for path, text in {p: x for env in ENVS for p, x in render(cfg, env).items()}.items():
        old = path.read_text(encoding="utf-8") if path.exists() else None
        if old != text:
            changed.append(path.relative_to(ROOT).as_posix())
            if "--check" not in argv:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    verb = "would change" if "--check" in argv else "updated"
    for c in changed:
        print(f"render-standby: {verb} {c}")
    print(f"render-standby: {len(changed)} file(s) {verb}")
    return 1 if changed and "--check" in argv else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
