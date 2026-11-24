#!/usr/bin/env python3
"""Write the admin entry of the central cluster from config/platform.yaml: Gateway API objects, oauth2-proxy, the private CA issuer.

Usage: render_admin_gateway.py [--check]. Without --check the files are rewritten; with it the exit code is 1 when any file would change.
Files: deploy/platform/admin-gateway/manifests/ (namespaces, Gateway and Certificate, HTTPRoutes, ReferenceGrants, stable tool Services,
oauth2-proxy with its ExternalSecrets, PodDisruptionBudgets and NetworkPolicies) and deploy/platform/aws-privateca-issuer/manifests/.
"""
import sys
from pathlib import Path

import yaml

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "config" / "platform.yaml").exists())
ADMIN = ROOT / "deploy" / "platform" / "admin-gateway" / "manifests"
ISSUER = ROOT / "deploy" / "platform" / "aws-privateca-issuer" / "manifests"
CENTRAL_ENV = "shared-services"
GATEWAY_NS = "istio-ingress-admin"
PROXY_NS = "admin-proxy"
GATEWAY = "admin"
CERT_SECRET = "admin-wildcard-tls"
ISSUER_NAME = "admin-private-ca"
# Placeholder until the private CA exists: the CA id is known after the CA is created
CA_ID = "00000000-0000-0000-0000-000000000000"
PROXY_IMAGE = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.6@sha256:c3415e8660af553f5e18f5d90db050614c02493c0ac6260ac59442f6d9b12048"
PROXY_PORT = 4180
PROXY_REPLICAS = 2
# Tools that sign people in themselves are routed straight to their Service.
# With `selector`, a Service of this package selects the pods by labels that do not depend on the Helm release name: the release name is
# the Application name (it holds the cluster name) and the chart Service names depend on it. Without it the release name is fixed.
DIRECT = {
    "argocd": {"ns": "argocd", "service": "admin-argocd", "port": 80, "target": 8080, "selector": {"app.kubernetes.io/name": "argocd-server"}},
    "vault": {"ns": "vault", "service": "admin-vault", "port": 8200, "target": 8200,
              "selector": {"app.kubernetes.io/name": "vault", "component": "server", "vault-active": "true"}},
    "grafana": {"ns": "monitoring", "service": "grafana", "port": 80},
    "sentry": {"ns": "sentry", "service": "sentry-web", "port": 9000},
}
# Tools without a sign-in of their own go through one oauth2-proxy each: a proxy picks its upstream by path, not by host.
PROXIED = {
    "alertmanager": {"ns": "monitoring", "service": "admin-alertmanager", "port": 9093, "target": 9093,
                     "selector": {"app.kubernetes.io/name": "alertmanager"}, "path": "/"},
    "vmui": {"ns": "victoria-metrics", "service": "vm-victoria-metrics-cluster-vmselect", "port": 8481, "path": "/select/0/vmui/"},
    "prometheus": {"ns": "monitoring", "service": "admin-prometheus", "port": 9090, "target": 9090,
                   "selector": {"app.kubernetes.io/name": "prometheus"}, "path": "/"},
}
OIDC_FIELDS = {
    "OAUTH2_PROXY_CLIENT_ID": "client_id",
    "OAUTH2_PROXY_CLIENT_SECRET": "client_secret",
    "OAUTH2_PROXY_OIDC_ISSUER_URL": "issuer",
}
LOAD_BALANCER = {
    "service.beta.kubernetes.io/aws-load-balancer-scheme": "internal",
    "service.beta.kubernetes.io/aws-load-balancer-type": "external",
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip",
    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled": "true",
}
NS_LABEL = "kubernetes.io/metadata.name"


def dump(docs, head):
    text = "".join(f"---\n{yaml.dump(d, Dumper=yaml.SafeDumper, sort_keys=False)}" for d in docs)
    return f"# {head}\n{text}"


def meta(name, namespace, **extra):
    return {"name": name, "namespace": namespace, **extra}


def proxy_name(tool):
    return f"oauth2-proxy-{tool}"


def backend(tool):
    if tool in PROXIED:
        return PROXY_NS, proxy_name(tool), PROXY_PORT
    spec = DIRECT[tool]
    return spec["ns"], spec["service"], spec["port"]


def namespaces():
    return [{"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": name, "annotations": {"argocd.argoproj.io/sync-wave": "-2"}, **labels}}
            for name, labels in ((GATEWAY_NS, {}), (PROXY_NS, {"labels": {"pod-security.kubernetes.io/enforce": "restricted"}}))]


def gateway(zone):
    return [
        {"apiVersion": "gateway.networking.k8s.io/v1", "kind": "Gateway", "metadata": meta(GATEWAY, GATEWAY_NS),
         "spec": {
             "gatewayClassName": "istio",
             # The annotations are copied to the Service that Istio creates; the AWS Load Balancer Controller then builds an internal NLB
             "infrastructure": {"annotations": dict(LOAD_BALANCER)},
             "listeners": [{
                 "name": "https", "port": 443, "protocol": "HTTPS", "hostname": f"*.{zone}",
                 "tls": {"mode": "Terminate", "certificateRefs": [{"kind": "Secret", "name": CERT_SECRET}]},
                 "allowedRoutes": {"kinds": [{"group": "gateway.networking.k8s.io", "kind": "HTTPRoute"}],
                                   "namespaces": {"from": "Selector", "selector": {"matchLabels": {NS_LABEL: GATEWAY_NS}}}},
             }]}},
        {"apiVersion": "cert-manager.io/v1", "kind": "Certificate", "metadata": meta(CERT_SECRET, GATEWAY_NS),
         "spec": {
             "secretName": CERT_SECRET, "dnsNames": [f"*.{zone}"], "duration": "720h", "renewBefore": "240h",
             "privateKey": {"algorithm": "ECDSA", "size": 256, "rotationPolicy": "Always"},
             "issuerRef": {"group": "awspca.cert-manager.io", "kind": "AWSPCAClusterIssuer", "name": ISSUER_NAME}}},
    ]


def routes(zone):
    docs = []
    for tool in (*DIRECT, *PROXIED):
        ns, service, port = backend(tool)
        rules = []
        if tool in PROXIED and PROXIED[tool]["path"] != "/":
            # The UI lives under a path: the bare host opens it
            rules.append({"matches": [{"path": {"type": "Exact", "value": "/"}}],
                          "filters": [{"type": "RequestRedirect", "requestRedirect": {
                              "path": {"type": "ReplaceFullPath", "replaceFullPath": PROXIED[tool]["path"]}, "statusCode": 302}}]})
        rules.append({"backendRefs": [{"name": service, "namespace": ns, "port": port}]})
        docs.append({
            "apiVersion": "gateway.networking.k8s.io/v1", "kind": "HTTPRoute", "metadata": meta(tool, GATEWAY_NS),
            "spec": {"parentRefs": [{"name": GATEWAY, "sectionName": "https"}], "hostnames": [f"{tool}.{zone}"], "rules": rules}})
    return docs


def reference_grants():
    wanted = {}
    for tool in (*DIRECT, *PROXIED):
        ns, service, _ = backend(tool)
        wanted.setdefault(ns, []).append(service)
    return [{
        "apiVersion": "gateway.networking.k8s.io/v1beta1", "kind": "ReferenceGrant", "metadata": meta("admin-gateway-routes", ns),
        "spec": {"from": [{"group": "gateway.networking.k8s.io", "kind": "HTTPRoute", "namespace": GATEWAY_NS}],
                 "to": [{"group": "", "kind": "Service", "name": s} for s in sorted(wanted[ns])]}} for ns in sorted(wanted)]


def tool_services():
    return [{"apiVersion": "v1", "kind": "Service", "metadata": meta(spec["service"], spec["ns"], labels={"app.kubernetes.io/part-of": "admin-gateway"}),
             "spec": {"selector": spec["selector"], "ports": [{"name": "http", "port": spec["port"], "targetPort": spec["target"]}]}}
            for spec in {**DIRECT, **PROXIED}.values() if "selector" in spec]


def external_secrets(prefix):
    generator = {"apiVersion": "generators.external-secrets.io/v1alpha1", "kind": "Password", "name": "oauth2-proxy-cookie"}
    store = {"kind": "ClusterSecretStore", "name": "aws-secrets-manager"}
    return [
        {"apiVersion": "generators.external-secrets.io/v1alpha1", "kind": "Password", "metadata": meta("oauth2-proxy-cookie", PROXY_NS),
         "spec": {"length": 32, "digits": 6, "symbols": 0, "noUpper": False, "allowRepeat": True}},
        # Generated once and kept: a new value would end every session
        {"apiVersion": "external-secrets.io/v1", "kind": "ExternalSecret",
         "metadata": meta("oauth2-proxy-cookie", PROXY_NS, annotations={"argocd.argoproj.io/sync-wave": "-1"}),
         "spec": {"refreshInterval": "0", "target": {"name": "oauth2-proxy-cookie", "creationPolicy": "Owner"},
                  "dataFrom": [{"sourceRef": {"generatorRef": generator},
                                "rewrite": [{"regexp": {"source": "password", "target": "OAUTH2_PROXY_COOKIE_SECRET"}}]}]}},
        {"apiVersion": "external-secrets.io/v1", "kind": "ExternalSecret",
         "metadata": meta("oauth2-proxy-oidc", PROXY_NS, annotations={"argocd.argoproj.io/sync-wave": "-1"}),
         "spec": {"refreshInterval": "1h", "secretStoreRef": store, "target": {"name": "oauth2-proxy-oidc", "creationPolicy": "Owner"},
                  "data": [{"secretKey": key, "remoteRef": {"key": f"{prefix}/{CENTRAL_ENV}/proxy/oidc", "property": prop}}
                           for key, prop in OIDC_FIELDS.items()]}},
    ]


def proxy(tool, zone, group):
    name = proxy_name(tool)
    spec = PROXIED[tool]
    labels = {"app.kubernetes.io/name": name, "app.kubernetes.io/part-of": "admin-gateway"}
    selector = {"app.kubernetes.io/name": name}
    upstream = f"http://{spec['service']}.{spec['ns']}.svc.cluster.local:{spec['port']}"
    args = [
        "--provider=oidc", f"--upstream={upstream}", f"--http-address=0.0.0.0:{PROXY_PORT}", f"--redirect-url=https://{tool}.{zone}/oauth2/callback",
        "--oidc-groups-claim=groups", f"--allowed-group={group}", "--scope=openid email groups", "--code-challenge-method=S256",
        # Who may enter is decided by the group only
        "--email-domain=*", "--skip-provider-button=true", "--reverse-proxy=true",
        f"--cookie-name=__Host-{name}", "--cookie-secure=true", "--cookie-httponly=true", "--cookie-samesite=lax", "--cookie-expire=8h",
        "--cookie-refresh=1h", "--pass-access-token=false", "--pass-authorization-header=false",
    ]

    def probe(path):
        return {"httpGet": {"path": path, "port": "http"}, "periodSeconds": 10}

    return [
        {"apiVersion": "apps/v1", "kind": "Deployment", "metadata": meta(name, PROXY_NS, labels=labels),
         "spec": {
             "replicas": PROXY_REPLICAS, "selector": {"matchLabels": selector},
             "template": {"metadata": {"labels": labels}, "spec": {
                 "automountServiceAccountToken": False,
                 "securityContext": {"runAsNonRoot": True, "runAsUser": 65532, "seccompProfile": {"type": "RuntimeDefault"}},
                 "topologySpreadConstraints": [{"maxSkew": 1, "topologyKey": "topology.kubernetes.io/zone", "whenUnsatisfiable": "ScheduleAnyway",
                                                "labelSelector": {"matchLabels": selector}}],
                 "containers": [{
                     "name": "oauth2-proxy", "image": PROXY_IMAGE, "args": args,
                     "ports": [{"name": "http", "containerPort": PROXY_PORT}],
                     "envFrom": [{"secretRef": {"name": "oauth2-proxy-oidc"}}, {"secretRef": {"name": "oauth2-proxy-cookie"}}],
                     "readinessProbe": probe("/ready"), "livenessProbe": probe("/ping"),
                     "resources": {"requests": {"cpu": "50m", "memory": "64Mi"}, "limits": {"memory": "128Mi"}},
                     "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True, "capabilities": {"drop": ["ALL"]}},
                 }]}}}},
        {"apiVersion": "v1", "kind": "Service", "metadata": meta(name, PROXY_NS, labels=labels),
         "spec": {"selector": selector, "ports": [{"name": "http", "port": PROXY_PORT, "targetPort": "http"}]}},
        {"apiVersion": "policy/v1", "kind": "PodDisruptionBudget", "metadata": meta(name, PROXY_NS),
         "spec": {"minAvailable": 1, "selector": {"matchLabels": selector}}},
    ]


def network_policies():
    docs = [{"apiVersion": "networking.k8s.io/v1", "kind": "NetworkPolicy", "metadata": meta("default-deny", PROXY_NS),
             "spec": {"podSelector": {}, "policyTypes": ["Ingress", "Egress"]}}]
    for tool, spec in PROXIED.items():
        docs.append({
            "apiVersion": "networking.k8s.io/v1", "kind": "NetworkPolicy", "metadata": meta(proxy_name(tool), PROXY_NS),
            "spec": {
                "podSelector": {"matchLabels": {"app.kubernetes.io/name": proxy_name(tool)}}, "policyTypes": ["Ingress", "Egress"],
                # Only the pods of the admin Gateway may send requests
                "ingress": [{"from": [{"namespaceSelector": {"matchLabels": {NS_LABEL: GATEWAY_NS}},
                                       "podSelector": {"matchLabels": {"gateway.networking.k8s.io/gateway-name": GATEWAY}}}],
                             "ports": [{"protocol": "TCP", "port": PROXY_PORT}]}],
                "egress": [
                    {"to": [{"namespaceSelector": {"matchLabels": {NS_LABEL: "kube-system"}}}],
                     "ports": [{"protocol": "UDP", "port": 53}, {"protocol": "TCP", "port": 53}]},
                    {"to": [{"namespaceSelector": {"matchLabels": {NS_LABEL: spec["ns"]}}}],
                     "ports": [{"protocol": "TCP", "port": spec.get("target", spec["port"])}]},
                    # Okta, outside the cluster; the firewall of the egress path allows only its host
                    {"ports": [{"protocol": "TCP", "port": 443}]},
                ]}})
    return docs


def issuer(cfg):
    account = cfg["accounts"]["shared_services"]
    region = cfg["regions"]["working"]
    return [{"apiVersion": "awspca.cert-manager.io/v1beta1", "kind": "AWSPCAClusterIssuer", "metadata": {"name": ISSUER_NAME},
             "spec": {"arn": f"arn:aws:acm-pca:{region}:{account}:certificate-authority/{CA_ID}", "region": region}}]


def render(cfg):
    zone = cfg["dns"]["admin_zone"]
    prefix = cfg["naming"]["prefix"]
    group = cfg["access"]["grafana_groups"]["admin"]
    head = "Generated by render_admin_gateway.py from config/platform.yaml; edit the source, not this file."
    files = {
        ADMIN / "namespaces.yaml": namespaces(),
        ADMIN / "gateway.yaml": gateway(zone),
        ADMIN / "routes.yaml": routes(zone),
        ADMIN / "referencegrants.yaml": reference_grants(),
        ADMIN / "tool-services.yaml": tool_services(),
        ADMIN / "oauth2-proxy-secret.yaml": external_secrets(prefix),
        ADMIN / "oauth2-proxy.yaml": [d for tool in PROXIED for d in proxy(tool, zone, group)],
        ADMIN / "oauth2-proxy-network.yaml": network_policies(),
        ISSUER / "clusterissuer.yaml": issuer(cfg),
    }
    return {path: dump(docs, head) for path, docs in files.items()}


def main(argv):
    cfg = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
    changed = []
    for path, text in render(cfg).items():
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            changed.append(path.relative_to(ROOT).as_posix())
            if "--check" not in argv:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
    verb = "would change" if "--check" in argv else "updated"
    for c in changed:
        print(f"render-admin-gateway: {verb} {c}")
    print(f"render-admin-gateway: {len(changed)} file(s) {verb}")
    return 1 if changed and "--check" in argv else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
