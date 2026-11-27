#!/usr/bin/env python3
"""Builds the pilot-light compute of a standby region and registers its clusters in Argo CD (run by .github/workflows/dr-compute-build.yml).

apply: terragrunt apply of the eks, memorydb, karpenter and iam-workloads units of every cell with PAY_STANDBY_COMPUTE=true. All cells run in
parallel; inside a cell eks and memorydb run together, karpenter follows eks and iam-workloads follows both (its dependencies).
With --state-region the Terraform state is the bootstrap replica bucket of that region (PAY_STATE_REGION), for a switch while the working
region is down.
argocd-core: installs Argo CD in core mode and the deploy/argocd release into the first standby cell cluster, for when the central Argo CD
runs in the failed region.
register: writes an Argo CD cluster Secret per cell with the labels the ApplicationSets select on (kubectl apply, so a re-run is a no-op), then
drops the region from pilotLight of the deploy/argocd release, so the ApplicationSets generate its Applications.
wait-apps: waits until the Applications of the region are synced and healthy (prod is gated: only their presence is checked).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UNITS = ("eks", "memorydb", "karpenter", "iam-workloads")
ARGO_HELM = "https://argoproj.github.io/argo-helm"
POLL_SECONDS = 30


def log(event, **fields):
    print(json.dumps({"event": event, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **fields}, sort_keys=True), flush=True)


def short(region):
    a, b, c = region.split("-")
    return f"{a}{b[0]}{c}"


def platform_value(root, section, key):
    # config/platform.yaml without a YAML library: <section>.<key> of a plain two-level mapping
    m = re.search(rf"^{section}:\s*\n(?:[ \t]+.*\n|\s*\n)*?[ \t]+{key}:\s*([a-z0-9-]+)", (root / "config/platform.yaml").read_text(), re.MULTILINE)
    if not m:
        raise SystemExit(f"{section}.{key} not found in config/platform.yaml")
    return m.group(1)


def cells(root, env, region):
    base = root / "infra/live" / env / region
    found = sorted(p.parent.parent.name for p in base.glob("*/eks/terragrunt.hcl"))
    if not found:
        raise SystemExit(f"no standby compute units under {base.relative_to(root)}")
    return found


def component(unit_dir):
    m = re.search(r'^\s*component\s*=\s*"([^"]+)"', (unit_dir / "terragrunt.hcl").read_text(), re.MULTILINE)
    return m.group(1) if m else None


def argocd_chart_version(root):
    # the version the addon-argocd ApplicationSet pins (Renovate bumps it there)
    m = re.search(r"chart: argo-cd\s*\n\s*targetRevision:\s*([0-9][0-9A-Za-z.+-]*)", (root / "deploy/argocd/templates/addons/argocd.yaml").read_text())
    if not m:
        raise ValueError("argo-cd chart version not found in deploy/argocd/templates/addons/argocd.yaml")
    return m.group(1)


class Builder:
    def __init__(self, args, run=subprocess.run, now=time.monotonic, sleep=time.sleep):
        self.a = args
        self.run = run
        self.now = now
        self.sleep = sleep

    def eks_name(self, cell, prefix):
        return f"{prefix}-{self.a.env}-{short(self.a.region)}-{component(self.a.root / 'infra/live' / self.a.env / self.a.region / cell / 'eks')}"

    def apply(self, cell, unit):
        unit_dir = self.a.root / "infra/live" / self.a.env / self.a.region / cell / unit
        if not (unit_dir / "terragrunt.hcl").exists():
            log("skip-unit", cell=cell, unit=unit, reason="no unit")
            return
        cmd = ["terragrunt", "run", "--non-interactive", "--working-dir", str(unit_dir), "--", "apply", "-input=false", "-auto-approve"]
        if self.a.dry_run:
            log("would-apply", cell=cell, unit=unit, command=" ".join(cmd))
            return
        begun = self.now()
        env = {**os.environ, "PAY_STANDBY_COMPUTE": "true", **({"PAY_STATE_REGION": self.a.state_region} if self.a.state_region else {})}
        done = self.run(cmd, env=env, capture_output=True, text=True, check=False)
        # one block per unit, so parallel applies do not interleave in the job log
        print(f"::group::{cell}/{unit}\n{done.stdout}{done.stderr}::endgroup::", flush=True)
        log("applied" if done.returncode == 0 else "apply-failed", cell=cell, unit=unit, seconds=round(self.now() - begun, 1))
        if done.returncode != 0:
            raise RuntimeError(f"{cell}/{unit} failed")

    def build_cell(self, cell):
        begun = self.now()
        with ThreadPoolExecutor(max_workers=2) as pool:
            eks, memorydb = pool.submit(self.apply, cell, "eks"), pool.submit(self.apply, cell, "memorydb")
            eks.result()
            karpenter = pool.submit(self.apply, cell, "karpenter")
            memorydb.result()
            karpenter.result()
        self.apply(cell, "iam-workloads")
        log("cell-built", cell=cell, seconds=round(self.now() - begun, 1))

    def build(self):
        names = cells(self.a.root, self.a.env, self.a.region)
        begun = self.now()
        with ThreadPoolExecutor(max_workers=len(names)) as pool:
            futures = {cell: pool.submit(self.build_cell, cell) for cell in names}
        failed = sorted(cell for cell, f in futures.items() if f.exception() is not None)
        log("compute-built" if not failed else "compute-build-failed", cells=names, failed=failed, seconds=round(self.now() - begun, 1))
        return 1 if failed else 0

    def secret(self, cell, prefix, vault_cell):
        cluster = self.eks_name(cell, prefix)
        if self.a.dry_run:
            endpoint, ca = "https://dry-run.invalid", ""
        else:
            out = self.run(["aws", "eks", "describe-cluster", "--region", self.a.region, "--name", cluster, "--output", "json"],
                           capture_output=True, text=True, check=True).stdout
            info = json.loads(out)["cluster"]
            endpoint, ca = info["endpoint"], info["certificateAuthority"]["data"]
        # the destination name of applicationset-cells.yaml and applicationset-gated.yaml: <prefix>-<env>-<region-short>-<cell>
        name = f"{prefix}-{self.a.env}-{short(self.a.region)}-{cell}"
        auth = {"clusterName": cluster, **({"roleARN": self.a.argocd_role_arn} if self.a.argocd_role_arn else {})}
        return {
            "apiVersion": "v1", "kind": "Secret",
            "metadata": {"name": f"cluster-{name}", "namespace": self.a.argocd_namespace, "labels": {
                "argocd.argoproj.io/secret-type": "cluster", "payments-platform/environment": self.a.env, "payments-platform/region": self.a.region,
                "payments-platform/cell": cell, "payments-platform/addons": "enabled", "payments-platform/central": "enabled",
                **({"payments-platform/vault": "enabled"} if cell == vault_cell else {})}},
            "type": "Opaque",
            "stringData": {"name": name, "server": endpoint,
                           "config": json.dumps({"awsAuthConfig": auth, "tlsClientConfig": {"insecure": False, "caData": ca}})},
        }

    def register(self):
        prefix, vault_cell = platform_value(self.a.root, "naming", "prefix"), platform_value(self.a.root, "vault", "cell")
        for cell in cells(self.a.root, self.a.env, self.a.region):
            doc = self.secret(cell, prefix, vault_cell)
            if self.a.dry_run:
                log("would-register", cell=cell, name=doc["stringData"]["name"], labels=doc["metadata"]["labels"])
                continue
            self.run(["kubectl", "apply", "-f", "-"], input=json.dumps(doc), capture_output=True, text=True, check=True)
            log("registered", cell=cell, name=doc["stringData"]["name"])
        return self.open_region()

    def open_region(self):
        if not self.a.apps_release:
            log("skip-open-region", reason="no --apps-release: remove the region from pilotLight of deploy/argocd by hand")
            return 0
        ns, rel = self.a.argocd_namespace, self.a.apps_release
        current = json.loads(self.run(["helm", "get", "values", rel, "-n", ns, "-o", "json"], capture_output=True, text=True, check=True).stdout or "{}")
        lights = (current or {}).get("pilotLight") or []
        keep = [p for p in lights if not (p.get("environment") == self.a.env and p.get("region") == self.a.region)]
        if keep == lights:
            log("skip-open-region", reason="region is not a pilot light in the release", release=rel)
            return 0
        cmd = ["helm", "upgrade", rel, str(self.a.root / "deploy/argocd"), "-n", ns, "--reuse-values", "--set-json", f"pilotLight={json.dumps(keep)}"]
        if self.a.dry_run:
            log("would-open-region", release=rel, pilot_light=keep)
            return 0
        self.run(cmd, capture_output=True, text=True, check=True)
        log("opened-region", release=rel, pilot_light=keep)
        return 0


    def core_values(self):
        # core mode: no API server, Dex or notifications; the controller, repo server and ApplicationSet controller reconcile from Git
        values = {"dex": {"enabled": False}, "notifications": {"enabled": False}, "server": {"replicas": 0}, "redis-ha": {"enabled": False},
                  "configs": {"cm": {"application.resourceTrackingMethod": "annotation", "admin.enabled": "false"}}}
        if self.a.argocd_controller_role_arn:
            values["controller"] = {"serviceAccount": {"annotations": {"eks.amazonaws.com/role-arn": self.a.argocd_controller_role_arn}}}
        return values

    def apps_values(self):
        import yaml  # only this action needs it; the workflow installs PyYAML

        out = self.run([sys.executable, str(self.a.root / "tools/config/argocd-values.py")], capture_output=True, text=True, check=True).stdout
        values = yaml.safe_load(out)
        values["pilotLight"] = [p for p in values.get("pilotLight") or [] if not (p.get("environment") == self.a.env and p.get("region") == self.a.region)]
        tags = self.run(["git", "tag", "--list", "v*", "--sort=-v:refname"], cwd=self.a.root, capture_output=True, text=True, check=True).stdout.split()
        if tags:
            # v* tags exist only after a prod rollout in all cells: the gated environments run that release
            values.setdefault("gated", {})["revision"] = tags[0]
        return values

    def argocd_core(self):
        prefix = platform_value(self.a.root, "naming", "prefix")
        host = self.eks_name(cells(self.a.root, self.a.env, self.a.region)[0], prefix)
        version, ns, rel = argocd_chart_version(self.a.root), self.a.argocd_namespace, self.a.apps_release or "platform-apps"
        steps = [
            (["aws", "eks", "update-kubeconfig", "--name", host, "--region", self.a.region, "--alias", "argocd"], None),
            (["helm", "upgrade", "--install", "argocd", "argo-cd", "--repo", ARGO_HELM, "--version", version, "-n", ns, "--create-namespace",
              "--wait", "--timeout", "10m", "-f", "-"], self.core_values),
            (["helm", "upgrade", "--install", rel, str(self.a.root / "deploy/argocd"), "-n", ns, "-f", "-"], self.apps_values),
        ]
        for cmd, values in steps:
            if self.a.dry_run:
                log("would-run", command=" ".join(cmd))
                continue
            begun = self.now()
            self.run(cmd, input=None if values is None else json.dumps(values()), capture_output=True, text=True, check=True)
            log("ran", command=" ".join(cmd[:4]), seconds=round(self.now() - begun, 1))
        log("argocd-core-ready", cluster=host, chart=version, release=rel)
        return 0

    def applications(self):
        items = json.loads(self.run(["kubectl", "get", "applications.argoproj.io", "-n", self.a.argocd_namespace, "-o", "json"],
                                    capture_output=True, text=True, check=True).stdout).get("items", [])
        # payments-cell-<env>-<region>-<cell>, payments-locker-<env>-<region>, payments-control-center-<env>-<region>
        marker = f"-{self.a.env}-{self.a.region}"
        return {i["metadata"]["name"]: i for i in items if i["metadata"]["name"].endswith(marker) or f"{marker}-" in i["metadata"]["name"]}

    @staticmethod
    def status(app):
        st = app.get("status", {})
        return st.get("sync", {}).get("status"), st.get("health", {}).get("status")

    def wait_apps(self):
        if self.a.dry_run:
            log("would-wait-apps", env=self.a.env, region=self.a.region, dr_sync=self.a.dr_sync)
            return 0
        deadline = self.now() + self.a.wait_minutes * 60
        while True:
            apps = self.applications()
            if apps and self.a.env == "prod":
                return self.dr_sync(apps, deadline) if self.a.dr_sync else self.gated_present(apps)
            if apps and all(self.status(a) == ("Synced", "Healthy") for a in apps.values()):
                log("apps-healthy", apps=sorted(apps))
                return 0
            if self.now() + POLL_SECONDS > deadline:
                log("apps-not-ready", apps={k: list(self.status(a)) for k, a in apps.items()})
                return 1
            self.sleep(POLL_SECONDS)

    def gated_present(self, apps):
        log("apps-present", apps=sorted(apps), note="prod is gated: sync each cell by hand")
        return 0

    def dr_sync(self, apps, deadline):
        # DR only: one sync per Application at the revision prod already runs, cell by cell with a health check in between; the
        # ApplicationSets keep their manual gate for new releases
        tags = self.run(["git", "tag", "--list", "v*", "--sort=-v:refname"], cwd=self.a.root, capture_output=True, text=True, check=True).stdout.split()
        if not tags:
            log("dr-sync-refused", reason="no v* tag: prod has no approved release to sync")
            return 1
        release = tags[0]
        for name in sorted(apps, key=sync_order):
            pinned = {src.get("targetRevision") for src in apps[name]["spec"].get("sources", [apps[name]["spec"].get("source", {})]) if src.get("chart") is None}
            # the chart source pins the release; the values source must follow it too, never a branch
            if pinned != {release}:
                log("dr-sync-refused", app=name, pinned=sorted(r for r in pinned if r), release=release)
                return 1
            if self.status(apps[name]) == ("Synced", "Healthy"):
                log("dr-sync-skip", app=name, reason="already synced and healthy")
                continue
            op = {"operation": {"initiatedBy": {"username": "dr-compute-build"}, "info": [{"name": "reason", "value": f"dr switch at {release}"}],
                                "sync": {"prune": False}}}
            self.run(["kubectl", "patch", "applications.argoproj.io", name, "-n", self.a.argocd_namespace, "--type", "merge", "-p", json.dumps(op)],
                     capture_output=True, text=True, check=True)
            log("dr-sync-started", app=name, release=release)
            while True:
                current = self.applications().get(name, {})
                if self.status(current) == ("Synced", "Healthy") and current.get("status", {}).get("operationState", {}).get("phase") in (None, "Succeeded"):
                    log("dr-sync-healthy", app=name, release=release)
                    break
                if self.now() + POLL_SECONDS > deadline:
                    log("dr-sync-stopped", app=name, status=list(self.status(current)), reason="not healthy in time; later cells are not synced")
                    return 1
                self.sleep(POLL_SECONDS)
        log("dr-sync-done", apps=sorted(apps, key=sync_order), release=release)
        return 0


def sync_order(name):
    # cell-0 first, the other cells in order, the spare last among the cells, then locker, edge and control-center
    cell = re.search(r"-(cell-\d+|spare)$", name)
    if cell is None:
        return (2, name)
    return (1, "~") if cell.group(1) == "spare" else (0, cell.group(1))


TRIGGERS = ("drill", "switch")


def resolve_state(trigger, state, confirm, env):
    # A drill must never write the replica state bucket; a real switch must be confirmed (the Lambda sends the phrase itself)
    if trigger not in TRIGGERS:
        raise ValueError(f"trigger must be one of {TRIGGERS}")
    if trigger == "drill":
        if state == "replica":
            raise ValueError("a drill runs against the working state; state=replica is only for a real switch")
        return "working"
    if confirm != f"switch {env}":
        raise ValueError(f"a real switch needs confirm='switch {env}'")
    return state if state in ("working", "replica") else "replica"


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Build the standby compute of a pilot-light region and register it in Argo CD")
    ap.add_argument("action", choices=["resolve-state", "apply", "argocd-core", "register", "wait-apps"])
    ap.add_argument("--env", required=True, choices=["stage", "prod"])
    ap.add_argument("--region", required=True, help="standby region, for example us-east-1")
    ap.add_argument("--argocd-namespace", default="argocd")
    ap.add_argument("--argocd-role-arn", default="", help="role Argo CD assumes for the new clusters (awsAuthConfig.roleARN)")
    ap.add_argument("--apps-release", default="", help="helm release of deploy/argocd whose pilotLight list holds the region")
    ap.add_argument("--argocd-controller-role-arn", default="", help="argocd-core: IAM role of the application controller (IRSA)")
    ap.add_argument("--state-region", default="", help="read and write Terraform state in the replica bucket of this region")
    ap.add_argument("--dr-sync", action="store_true", help="wait-apps: sync gated prod Applications once at the deployed release, cell by cell")
    ap.add_argument("--trigger", default="drill", help="resolve-state: drill or switch")
    ap.add_argument("--state", default="auto", choices=["auto", "working", "replica"], help="resolve-state: requested Terraform state")
    ap.add_argument("--confirm", default="", help="resolve-state: 'switch <env>' for a real switch")
    ap.add_argument("--wait-minutes", type=float, default=20, help="wait-apps: minutes before giving up")
    ap.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    ap.add_argument("--dry-run", action="store_true")
    ns = ap.parse_args(argv)
    for region in filter(None, (ns.region, ns.state_region)):
        if not re.fullmatch(r"[a-z]{2}-[a-z]+-[0-9]", region):
            ap.error("regions must look like us-east-1")
    return ns


def main(argv=None, **kw):
    ns = parse_args(argv if argv is not None else sys.argv[1:])
    if ns.action == "resolve-state":
        try:
            print(resolve_state(ns.trigger, ns.state, ns.confirm, ns.env))
        except ValueError as exc:
            # stderr: the workflow captures stdout as the state
            print(f"::error::{exc}", file=sys.stderr)
            return 2
        return 0
    builder = Builder(ns, **kw)
    try:
        return {"apply": builder.build, "argocd-core": builder.argocd_core, "register": builder.register, "wait-apps": builder.wait_apps}[ns.action]()
    except (subprocess.CalledProcessError, RuntimeError, KeyError, ValueError) as exc:
        log("error", error=type(exc).__name__, reason=str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
