"""The EKS clusters of the platform, read from the live tree: every infra/live/<env>/<region>/<component>/eks unit is one cluster.

Shared by tools/config/argocd-values.py (the Argo CD cluster Secrets) and tools/config/render_vault.py (one Vault jwt auth
mount per cluster), so a cluster added in Terraform is registered everywhere without a second list to keep in step.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SHORT = {"eu-central-1": "euc1", "us-east-1": "use1"}
CELLS = ("cell-0", "cell-1", "cell-2", "cell-3", "spare")


def clusters(cfg, live=None):
    prefix = cfg["naming"]["prefix"]
    live = live or ROOT / "infra" / "live"
    out = []
    for unit in sorted(live.glob("*/*/*/eks/terragrunt.hcl")):
        component, region, env = unit.parent.parent.name, unit.parent.parent.parent.name, unit.parent.parent.parent.parent.name
        c = {"environment": env, "region": region, "component": component,
             "name": f"{prefix}-{env}-{SHORT[region]}-{component}"}
        if component == "central":
            # Argo CD and Vault run here; the cluster Secret needs no credentials
            c.update(inCluster=True, eksName=f"{prefix}-{env}-{SHORT[region]}-central", labels={"payments-platform/central": "enabled", "payments-platform/vault": "enabled"})
        elif component == "analytics":
            c["labels"] = {"payments-platform/kafka": "enabled"}
        out.append(c)
    return out


def kind(component):
    """What runs on the cluster, for the Vault roles of its auth mount."""
    if component in CELLS:
        return "cell"
    return component
