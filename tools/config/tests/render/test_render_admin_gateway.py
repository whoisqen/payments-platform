import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "render"))
import render_admin_gateway as r  # noqa: E402

CFG = yaml.safe_load((r.ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = r.render(CFG)
ZONE = CFG["dns"]["admin_zone"]


def docs(path):
    return [d for d in yaml.safe_load_all(OUT[path]) if d]


class RenderAdminGatewayTest(unittest.TestCase):
    def test_committed_files_are_current(self):
        for path, text in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), text, f"run render_admin_gateway.py: {path}")

    def test_gateway_is_internal_https_only_with_selected_routes(self):
        gw, cert = docs(r.ADMIN / "gateway.yaml")
        self.assertEqual(gw["spec"]["gatewayClassName"], "istio")
        ann = gw["spec"]["infrastructure"]["annotations"]
        self.assertEqual(ann["service.beta.kubernetes.io/aws-load-balancer-scheme"], "internal")
        self.assertEqual(ann["service.beta.kubernetes.io/aws-load-balancer-type"], "external")
        self.assertEqual(ann["service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"], "ip")
        (listener,) = gw["spec"]["listeners"]
        self.assertEqual((listener["protocol"], listener["tls"]["mode"]), ("HTTPS", "Terminate"))
        self.assertEqual(listener["allowedRoutes"]["namespaces"]["from"], "Selector")
        self.assertEqual(listener["tls"]["certificateRefs"][0]["name"], cert["spec"]["secretName"])
        self.assertEqual(cert["spec"]["dnsNames"], [f"*.{ZONE}"])
        self.assertEqual(cert["spec"]["issuerRef"]["kind"], "AWSPCAClusterIssuer")

    def test_ingest_gateway_needs_client_certificates_and_admits_only_environment_vpcs(self):
        gw, ca = docs(r.ADMIN / "ingest-gateway.yaml")
        refs = gw["spec"]["tls"]["frontend"]["default"]["validation"]["caCertificateRefs"]
        self.assertEqual(refs, [{"group": "", "kind": "ConfigMap", "name": ca["metadata"]["name"]}])
        self.assertIn("ca.crt", ca["data"])
        ranges = gw["spec"]["infrastructure"]["annotations"]["service.beta.kubernetes.io/load-balancer-source-ranges"].split(",")
        self.assertIn(CFG["network"]["prod"]["us-east-1"], ranges)
        self.assertNotIn(CFG["network"]["dev"]["egress"], ranges)
        self.assertTrue(all(l["tls"]["mode"] == "Terminate" for l in gw["spec"]["listeners"]))

    def test_ingest_routes_match_only_the_write_calls(self):
        listeners = {l["name"] for l in docs(r.ADMIN / "ingest-gateway.yaml")[0]["spec"]["listeners"]}
        for route in docs(r.ADMIN / "ingest-routes.yaml"):
            (rule,) = route["spec"]["rules"]
            (match,) = rule["matches"]
            self.assertIn(route["spec"]["parentRefs"][0]["sectionName"], listeners)
            if route["kind"] == "HTTPRoute":
                self.assertEqual((match["method"], match["path"]["type"]), ("POST", "Exact"))
            else:
                self.assertEqual(match["method"]["method"], "Export")
        hosts = {route["spec"]["hostnames"][0] for route in docs(r.ADMIN / "ingest-routes.yaml")}
        self.assertIn(CFG["central"]["metrics_remote_write_url"].split("/")[2], hosts)
        self.assertIn(CFG["central"]["traces_otlp_endpoint"].split(":")[0], hosts)

    def test_issuer_matches_the_certificate_reference(self):
        (issuer,) = docs(r.ISSUER / "clusterissuer.yaml")
        cert = docs(r.ADMIN / "gateway.yaml")[1]
        self.assertEqual(issuer["metadata"]["name"], cert["spec"]["issuerRef"]["name"])
        self.assertIn(CFG["accounts"]["shared_services"], issuer["spec"]["arn"])

    def test_every_tool_has_a_route_on_its_host(self):
        routes = {d["metadata"]["name"]: d for d in docs(r.ADMIN / "routes.yaml")}
        self.assertEqual(set(routes), {"argocd", "vault", "grafana", "sentry", "alertmanager", "vmui", "prometheus"})
        for tool, route in routes.items():
            self.assertEqual(route["spec"]["hostnames"], [f"{tool}.{ZONE}"])
            self.assertEqual(route["spec"]["parentRefs"][0]["name"], "admin")

    def test_tools_without_sign_in_go_through_their_own_proxy(self):
        routes = {d["metadata"]["name"]: d for d in docs(r.ADMIN / "routes.yaml")}
        for tool in ("alertmanager", "vmui", "prometheus"):
            ref = routes[tool]["spec"]["rules"][-1]["backendRefs"][0]
            self.assertEqual((ref["name"], ref["namespace"]), (f"oauth2-proxy-{tool}", r.PROXY_NS))
        for tool in ("argocd", "vault", "grafana", "sentry"):
            self.assertNotEqual(routes[tool]["spec"]["rules"][-1]["backendRefs"][0]["namespace"], r.PROXY_NS)

    def test_every_cross_namespace_backend_has_a_reference_grant(self):
        grants = {(d["metadata"]["namespace"], t["name"]) for d in docs(r.ADMIN / "referencegrants.yaml") for t in d["spec"]["to"]}
        for route in docs(r.ADMIN / "routes.yaml"):
            for rule in route["spec"]["rules"]:
                for ref in rule.get("backendRefs", []):
                    self.assertIn((ref["namespace"], ref["name"]), grants)

    def test_routes_contain_no_ingress_or_istio_networking_kinds(self):
        for path, text in OUT.items():
            for d in yaml.safe_load_all(text):
                self.assertNotIn("Ingress", d["kind"])
                self.assertNotIn("networking.istio.io", d["apiVersion"])

    def test_proxies_demand_the_admin_group_and_are_hardened(self):
        deployments = [d for d in docs(r.ADMIN / "oauth2-proxy.yaml") if d["kind"] == "Deployment"]
        self.assertEqual(len(deployments), 3)
        for d in deployments:
            container = d["spec"]["template"]["spec"]["containers"][0]
            self.assertIn(f"--allowed-group={CFG['access']['grafana_groups']['admin']}", container["args"])
            self.assertIn("--oidc-groups-claim=groups", container["args"])
            self.assertIn("@sha256:", container["image"])
            self.assertGreaterEqual(d["spec"]["replicas"], 2)
            self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])

    def test_each_proxy_has_a_pdb_and_a_network_policy(self):
        names = {d["metadata"]["name"] for d in docs(r.ADMIN / "oauth2-proxy.yaml") if d["kind"] == "Deployment"}
        pdbs = {d["metadata"]["name"] for d in docs(r.ADMIN / "oauth2-proxy.yaml") if d["kind"] == "PodDisruptionBudget"}
        policies = {d["metadata"]["name"] for d in docs(r.ADMIN / "oauth2-proxy-network.yaml")}
        self.assertEqual(names, pdbs)
        self.assertLessEqual(names, policies)
        self.assertIn("default-deny", policies)

    def test_client_secret_comes_from_secrets_manager_by_convention(self):
        external = [d for d in docs(r.ADMIN / "oauth2-proxy-secret.yaml") if d["kind"] == "ExternalSecret" and "data" in d["spec"]][0]
        for item in external["spec"]["data"]:
            self.assertEqual(item["remoteRef"]["key"], f"{CFG['naming']['prefix']}/shared-services/proxy/oidc")


if __name__ == "__main__":
    unittest.main()
