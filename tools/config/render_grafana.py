#!/usr/bin/env python3
"""Write the deploy files of the central Loki, Tempo and Grafana from observability/dashboards and config/platform.yaml.

Usage: render_grafana.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
Files: deploy/platform/{loki,tempo}/storage.yaml (bucket and region), deploy/platform/grafana/manifests/ (one dashboards ConfigMap per
folder of observability/dashboards, the ExternalSecrets of the admin login and the OIDC client), and the organizations of
access.grafana_orgs: grafana.ini org mapping, per-organization providers, data sources and dashboard ConfigMaps, the PostSync Job
that creates the organizations (org-bootstrap.yaml).
"""
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
DASHBOARDS = ROOT / "observability" / "dashboards"
OUT = ROOT / "deploy" / "platform"
CENTRAL_ENV = "shared-services"
NAMESPACE = "monitoring"
FOLDER_TITLES = {"finops": "FinOps"}
OIDC_FIELDS = {
    "GF_AUTH_GENERIC_OAUTH_CLIENT_ID": "client_id",
    "GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET": "client_secret",
    "GF_AUTH_GENERIC_OAUTH_AUTH_URL": "auth_url",
    "GF_AUTH_GENERIC_OAUTH_TOKEN_URL": "token_url",
    "GF_AUTH_GENERIC_OAUTH_API_URL": "api_url",
}


DATABASE_FIELDS = {
    "GF_DATABASE_HOST": "host",
    "GF_DATABASE_NAME": "name",
    "GF_DATABASE_USER": "user",
    "GF_DATABASE_PASSWORD": "password",
}


# Strongest first. GrafanaAdmin is an Admin of its organization and a server administrator; Editor may use Explore (logs, traces,
# metrics) and silence alerts; Viewer sees the provisioned dashboards only. Dashboards are provisioned as code and cannot be changed in the UI.
RANK = {"GrafanaAdmin": 3, "Admin": 2, "Editor": 1, "Viewer": 0}
MAIN = "main"
BOOTSTRAP_SCRIPT = OUT / "grafana" / "scripts" / "bootstrap_orgs.py"
GROUP_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]*$")


def catalog():
    """Dashboards on disk: folder -> {file name: uid}."""
    return {folder.name: {p.name: json.loads(p.read_text(encoding="utf-8"))["uid"] for p in sorted(folder.glob("*.json"))}
            for folder in sorted(p for p in DASHBOARDS.iterdir() if p.is_dir())}


def resolved(image):
    return not str(image["repository"]).startswith("REPLACE_") and not set(image["digest"].removeprefix("sha256:")) <= {"0"}


def check_orgs(groups, orgs, dashboards, image):
    """Raise ValueError unless access.grafana_orgs is a consistent model: ids, groups, dashboards."""
    if MAIN not in orgs or orgs[MAIN].get("id") != 1 or orgs[MAIN].get("dashboards") != "all":
        raise ValueError("grafana_orgs.main must have id 1 and `dashboards: all`")
    ids = [o["id"] for o in orgs.values()]
    if sorted(ids) != list(range(1, len(ids) + 1)) or len({o["name"] for o in orgs.values()}) != len(orgs):
        raise ValueError("grafana_orgs need the ids 1, 2, 3, ... and different names")
    uids = {uid for files in dashboards.values() for uid in files.values()}
    placed = set()
    for key, org in orgs.items():
        for group, role in org["groups"].items():
            if group not in groups or role not in RANK:
                raise ValueError(f"grafana_orgs.{key}: unknown group `{group}` or role `{role}`")
            if role == "GrafanaAdmin" and key != MAIN:
                raise ValueError("GrafanaAdmin is a server role: only the main organization may grant it")
            if not GROUP_NAME.match(groups[group]):
                raise ValueError(f"group name `{groups[group]}` must not hold spaces, commas or colons")
            placed.add(group)
        wanted = org["dashboards"]
        if wanted != "all":
            for folder in wanted.get("folders", []):
                if folder not in dashboards:
                    raise ValueError(f"grafana_orgs.{key}: no dashboard folder `{folder}`")
            for uid in wanted.get("uids", []):
                if uid not in uids:
                    raise ValueError(f"grafana_orgs.{key}: no dashboard with uid `{uid}`")
        if key != MAIN and not org.get("datasources"):
            raise ValueError(f"grafana_orgs.{key}: list the data sources the dashboards need")
    if len(active(orgs)) > 1 and not resolved(image):
        raise ValueError("a provisioned organization needs its bootstrap Job: fill access.grafana_bootstrap_image first")
    if placed != set(groups):
        raise ValueError(f"every group needs an organization; missing: {sorted(set(groups) - placed)}")


def visible(org, dashboards):
    """Dashboards of an organization: folder -> [file names], in folder order; folders without a dashboard are left out."""
    if org["dashboards"] == "all":
        return {folder: list(files) for folder, files in dashboards.items()}
    wanted = org["dashboards"]
    result = {}
    for folder, files in dashboards.items():
        names = [name for name, uid in files.items() if folder in wanted.get("folders", []) or uid in wanted.get("uids", [])]
        if names:
            result[folder] = names
    return result


def active(orgs):
    """Organizations that are wired up: the main one always, the others once `provisioned` is true."""
    return {key: org for key, org in orgs.items() if key == MAIN or org.get("provisioned")}


def access(groups, orgs):
    """grafana.ini of the login: who may enter, in which organization and role, how long a session lives."""
    live = active(orgs)
    # The role expression decides the role in the main organization (and the server administrator flag) only; the other organizations
    # get their organization and role from org_mapping alone, so that nobody of them is also placed in the main organization
    main = sorted(orgs[MAIN]["groups"].items(), key=lambda item: -RANK[item[1]])
    expression = " || ".join(f"contains(groups[*], '{groups[group]}') && '{role}'" for group, role in main)
    mapping = ",".join(f"{groups[group]}:{org['id']}:{'Admin' if role == 'GrafanaAdmin' else role}"
                       for org in live.values() for group, role in org["groups"].items())
    allowed = [groups[group] for org in live.values() for group in org["groups"]]
    return {"grafana.ini": {
        "auth": {
            # People enter through the identity provider only; the local admin of the secret stays for a break-glass login at /login/local
            "disable_login_form": True,
            "oauth_allow_insecure_email_lookup": False,
            # Leaving a group takes effect at the next login at the latest: a session is renewed after 24 hours, idle ones end after 8
            "login_maximum_lifetime_duration": "24h",
            "login_maximum_inactive_lifetime_duration": "8h",
            "token_rotation_interval_minutes": 10,
        },
        "auth.generic_oauth": {
            "groups_attribute_path": "groups",
            # The groups are also the external organization names of org_mapping: <group>:<organization id>:<role>
            "org_attribute_path": "groups",
            "org_mapping": mapping,
            # The hard deny: a person outside these groups cannot log in, whatever the role and organization logic does
            "allowed_groups": ",".join(allowed),
            "role_attribute_path": expression,
            # No mapped group, no access (instead of a default role)
            "role_attribute_strict": True,
            "allow_assign_grafana_admin": True,
            "skip_org_role_sync": False,
            "allow_sign_up": True,
        },
        # A new user joins no organization by default: org_mapping places the person, so nobody lands in the main organization by accident
        "users": {"allow_sign_up": False, "auto_assign_org": False, "auto_assign_org_role": "Viewer", "viewers_can_edit": False, "editors_can_admin": False},
        "security": {"disable_gravatar": True, "cookie_secure": True, "cookie_samesite": "lax", "strict_transport_security": True, "allow_embedding": False},
        "snapshots": {"external_enabled": False},
        "explore": {"enabled": True},
    }}


def org_values(orgs, dashboards, main_datasources):
    """Helm values of the organizations other than the main one, and the unlabelled ConfigMaps they mount.

    Returns (values, config maps). The main organization keeps the sidecar and the datasources of values.yaml; the others get a provider
    per folder (path = the mounted ConfigMap) and a data source file with orgId. Values are keyed by new file names: Helm replaces lists.
    """
    providers, mounts, sources, config_maps = [], {}, [], {}
    by_uid = {d["uid"]: d for d in main_datasources}
    for key, org in active(orgs).items():
        if key == MAIN:
            continue
        for folder, names in visible(org, dashboards).items():
            name = f"org-{key}-{folder}"
            config_maps[name] = {n: (DASHBOARDS / folder / n).read_text(encoding="utf-8") for n in names}
            providers.append({"name": name, "orgId": org["id"], "folder": folder_title(folder), "type": "file", "disableDeletion": True,
                              "allowUiUpdates": False, "options": {"path": f"/var/lib/grafana/dashboards/{name}"}})
            mounts[name] = f"grafana-{name}"
        picked = [{"orgId": org["id"], **by_uid[uid]} for uid in org["datasources"]]
        if sum(bool(d.get("isDefault")) for d in picked) != 1:
            raise ValueError(f"grafana_orgs.{key}: exactly one data source must be the default")
        sources += picked
    if not providers:
        return {}, config_maps
    return {
        "dashboardProviders": {"org-providers.yaml": {"apiVersion": 1, "providers": providers}},
        "dashboardsConfigMaps": mounts,
        "datasources": {"datasources-orgs.yaml": {"apiVersion": 1, "datasources": sources}},
    }, config_maps


class LiteralDumper(yaml.SafeDumper):
    """Multi-line strings as `|` blocks, for the script of the bootstrap Job."""


LiteralDumper.add_representer(str, lambda dumper, text: dumper.represent_scalar("tag:yaml.org,2002:str", text, style="|" if "\n" in text else None))


def bootstrap(orgs, image, script):
    """ConfigMap and PostSync Job that create every organization of the config (also those not provisioned yet)."""
    name = "grafana-org-bootstrap"
    labels = {"app.kubernetes.io/name": name, "app.kubernetes.io/part-of": "payments-platform"}
    wanted = [{"id": org["id"], "name": org["name"]} for org in sorted(orgs.values(), key=lambda o: o["id"])]
    config_map = {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": name, "namespace": NAMESPACE, "labels": labels},
                  "data": {"bootstrap_orgs.py": script, "orgs.json": json.dumps({"orgs": wanted}, indent=2) + "\n"}}
    secret = lambda key: {"secretKeyRef": {"name": "grafana-admin", "key": key}}  # noqa: E731
    job = {
        "apiVersion": "batch/v1", "kind": "Job",
        "metadata": {"name": name, "namespace": NAMESPACE, "labels": labels,
                     "annotations": {"argocd.argoproj.io/hook": "PostSync", "argocd.argoproj.io/hook-delete-policy": "BeforeHookCreation"}},
        "spec": {
            # The script is idempotent, so a retry is safe; a mismatch of ids fails every time and stays visible as a failed hook
            "backoffLimit": 3, "activeDeadlineSeconds": 900,
            "template": {"metadata": {"labels": dict(labels)}, "spec": {
                "restartPolicy": "Never",
                "automountServiceAccountToken": False,
                "securityContext": {"runAsNonRoot": True, "runAsUser": 65532, "runAsGroup": 65532, "seccompProfile": {"type": "RuntimeDefault"}},
                "containers": [{
                    "name": "bootstrap",
                    "image": f"{image['repository']}@{image['digest']}",
                    "command": ["python3", "/bootstrap/bootstrap_orgs.py", "--orgs", "/bootstrap/orgs.json"],
                    "env": [{"name": "GRAFANA_URL", "value": f"http://grafana.{NAMESPACE}.svc"},
                            {"name": "GRAFANA_ADMIN_USER", "valueFrom": secret("admin-user")},
                            {"name": "GRAFANA_ADMIN_PASSWORD", "valueFrom": secret("admin-password")}],
                    "resources": {"requests": {"cpu": "50m", "memory": "64Mi"}, "limits": {"memory": "128Mi"}},
                    "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True, "capabilities": {"drop": ["ALL"]}},
                    "volumeMounts": [{"name": "script", "mountPath": "/bootstrap", "readOnly": True}],
                }],
                "volumes": [{"name": "script", "configMap": {"name": name}}],
            }},
        },
    }
    head = ("# Generated by tools/config/render_grafana.py from config/platform.yaml (access.grafana_orgs) and scripts/bootstrap_orgs.py; "
            "edit the sources, not this file.\n")
    return head + "---\n".join(yaml.dump(d, Dumper=LiteralDumper, sort_keys=False, width=1000) for d in (config_map, job))


def region_short(region):
    """eu-central-1 -> euc1, the code the resource names carry."""
    area, direction, number = region.split("-")
    return f"{area}{direction[0]}{number}"


def folder_title(level):
    if level in FOLDER_TITLES:
        return FOLDER_TITLES[level]
    head, _, tail = level.partition("-")
    return f"{head.upper()} {tail.capitalize()}" if tail else level.capitalize()


def dump(data, header):
    return f"# {header}\n" + yaml.dump(data, Dumper=yaml.SafeDumper, sort_keys=False, width=1000)


def external_secret(name, prefix, secret, mapping):
    return {
        "apiVersion": "external-secrets.io/v1",
        "kind": "ExternalSecret",
        "metadata": {"name": name, "namespace": NAMESPACE},
        "spec": {
            "refreshInterval": "1h",
            "secretStoreRef": {"kind": "ClusterSecretStore", "name": "aws-secrets-manager"},
            "target": {"name": name, "creationPolicy": "Owner"},
            "data": [{"secretKey": key, "remoteRef": {"key": f"{prefix}/{CENTRAL_ENV}/grafana/{secret}", "property": prop}}
                     for key, prop in mapping.items()],
        },
    }


def render(cfg):
    prefix = cfg["naming"]["prefix"]
    region = cfg["regions"]["working"]
    bucket = f"{prefix}-{CENTRAL_ENV}-{region_short(region)}"
    head = "Generated by tools/config/render_grafana.py from config/platform.yaml; edit the source, not this file."
    files = {
        OUT / "loki" / "storage.yaml": dump({"loki": {"storage": {
            "bucketNames": {k: f"{bucket}-loki" for k in ("chunks", "ruler", "admin")}, "s3": {"region": region}}}}, head),
        OUT / "tempo" / "storage.yaml": dump({"storage": {"trace": {"s3": {
            "bucket": f"{bucket}-tempo", "endpoint": f"s3.{region}.amazonaws.com", "region": region}}}}, head),
    }
    manifests = OUT / "grafana" / "manifests"
    dash_head = "Generated by tools/config/render_grafana.py from observability/dashboards; edit the dashboards, not this file."
    for folder in sorted(p for p in DASHBOARDS.iterdir() if p.is_dir()):
        data = {p.name: p.read_text(encoding="utf-8") for p in sorted(folder.glob("*.json"))}
        cm = {
            "apiVersion": "v1", "kind": "ConfigMap",
            "metadata": {"name": f"grafana-dashboards-{folder.name}", "namespace": NAMESPACE,
                         "labels": {"grafana_dashboard": "1"}, "annotations": {"grafana_folder": folder_title(folder.name)}},
            "data": data,
        }
        files[manifests / f"dashboards-{folder.name}.yaml"] = dump(cm, dash_head)
    groups, orgs, image = cfg["access"]["grafana_groups"], cfg["access"]["grafana_orgs"], cfg["access"]["grafana_bootstrap_image"]
    dashboards = catalog()
    check_orgs(groups, orgs, dashboards, image)
    main_values = yaml.safe_load((OUT / "grafana" / "values.yaml").read_text(encoding="utf-8"))
    extra, org_maps = org_values(orgs, dashboards, main_values["datasources"]["datasources.yaml"]["datasources"])
    files[OUT / "grafana" / "access.yaml"] = dump({**access(groups, orgs), **extra}, head)
    for name, data in org_maps.items():
        # No grafana_dashboard label: the sidecar would load these into the main organization; the provider of the organization mounts them
        cm = {"apiVersion": "v1", "kind": "ConfigMap", "metadata": {"name": f"grafana-{name}", "namespace": NAMESPACE}, "data": data}
        files[manifests / f"{name}.yaml"] = dump(cm, "Generated by tools/config/render_grafana.py from observability/dashboards and access.grafana_orgs; edit the sources, not this file.")
    if resolved(image):
        # A Job with a placeholder image would fail every sync (ImagePullBackOff); it is rendered once the owner has filled the image in
        files[manifests / "org-bootstrap.yaml"] = bootstrap(orgs, image, BOOTSTRAP_SCRIPT.read_text(encoding="utf-8"))
    files[manifests / "externalsecret-admin.yaml"] = dump(
        external_secret("grafana-admin", prefix, "admin", {"admin-user": "user", "admin-password": "password"}),
        "Generated by tools/config/render_grafana.py: the Grafana admin login, from AWS Secrets Manager.")
    files[manifests / "externalsecret-database.yaml"] = dump(
        external_secret("grafana-database", prefix, "database", DATABASE_FIELDS),
        "Generated by tools/config/render_grafana.py: the PostgreSQL that the Grafana replicas share, from AWS Secrets Manager.")
    files[manifests / "externalsecret-oidc.yaml"] = dump(
        external_secret("grafana-oidc", prefix, "oidc", OIDC_FIELDS),
        "Generated by tools/config/render_grafana.py: the OIDC client of Grafana as environment variables, from AWS Secrets Manager.")
    return files


def main(argv):
    cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
    files = render(cfg)
    changed = []
    for path, text in files.items():
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            changed.append(path.relative_to(ROOT).as_posix())
            if "--check" not in argv:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    manifests = OUT / "grafana" / "manifests"
    stale = [p for p in manifests.glob("*.yaml") if p not in files] if manifests.exists() else []
    for p in stale:
        changed.append(p.relative_to(ROOT).as_posix())
        if "--check" not in argv:
            p.unlink()
    verb = "would change" if "--check" in argv else "updated"
    for c in changed:
        print(f"render-grafana: {verb} {c}")
    print(f"render-grafana: {len(changed)} file(s) {verb}")
    return 1 if changed and "--check" in argv else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
