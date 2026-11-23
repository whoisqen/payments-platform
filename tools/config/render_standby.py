#!/usr/bin/env python3
"""Write deploy/envs/<env>/<standby region>/** from config/platform.yaml and the working region's cell list.

Usage: render_standby.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
ENVS = {"stage": "sandbox", "prod": "production"}  # environment -> RUN_ENV of its workloads


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
    # The cluster endpoint of the local global-database secondary: read-only until promotion, then the writer, so promotion needs no values change.
    writer = lambda name: f"{host(standby, 'aurora', name, '')}.cluster-{d['rds_suffix']}.{standby}.rds.amazonaws.com"
    reader = lambda name: f"{host(standby, 'aurora', name, '')}.cluster-ro-{d['rds_suffix']}.{standby}.rds.amazonaws.com"
    redis = lambda name: f"clustercfg.{prefix}-{ENV}-{s}-memorydb-{name}.{d['memorydb_suffix']}.memorydb.{standby}.amazonaws.com"
    base = ROOT / "deploy" / "envs" / ENV
    cells = sorted(p.name for p in (base / work).iterdir() if p.name.startswith("cell-") or p.name == "spare")
    files = {}
    files[f"{standby}/values.yaml"] = (
        "# Warm standby: receives no traffic while the working region is healthy; replicated data is local and promotion changes no values\n"
        f"global:\n  region: {standby}\n  dataCidrs:\n{lines(cidrs['data_cidrs'], 4)}  endpointCidrs:\n{lines(cidrs['endpoint_cidrs'], 4)}")
    for c in cells:
        w_host, r_host, r_redis = writer(c), reader(c), redis(c)
        files[f"{standby}/{c}/values.yaml"] = f"""# Cell {c} in the standby region: local Aurora secondary and MemoryDB, ready to become the writer on promotion; endpoints are placeholders until infra/live exports them
global:
  cell: {c}

migrations:
  enabled: false
  database:
    host: {w_host}

router:
  container:
    env:
      ROUTER__MASTER_DATABASE__HOST: {w_host}
      ROUTER__REPLICA_DATABASE__HOST: {r_host}
      ROUTER__REDIS__HOST: {r_redis}

drainer:
  container:
    env:
      DRAINER__MASTER_DATABASE__HOST: {w_host}
      DRAINER__REDIS__HOST: {r_redis}
      REDIS_ADDRESS: {r_redis}:6379

scheduler:
  producer:
    container:
      env:
        ROUTER__MASTER_DATABASE__HOST: {w_host}
        ROUTER__REDIS__HOST: {r_redis}
  consumer:
    container:
      env:
        ROUTER__MASTER_DATABASE__HOST: {w_host}
        ROUTER__REDIS__HOST: {r_redis}
        REDIS_ADDRESS: {r_redis}:6379
"""
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
