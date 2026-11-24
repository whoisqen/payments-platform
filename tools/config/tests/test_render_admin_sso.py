import sys
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "render"))
import render_admin_sso  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
CFG = yaml.safe_load((ROOT / "config" / "platform.yaml").read_text(encoding="utf-8"))
OUT = render_admin_sso.render(CFG)
GROUPS = CFG["access"]["grafana_groups"]


def text(name):
    return next(t for p, t in OUT.items() if p.name == name)


class RenderAdminSsoTest(unittest.TestCase):
    def test_committed_files_are_current(self):
        for path, body in OUT.items():
            self.assertEqual(path.read_text(encoding="utf-8"), body, f"run tools/config/render/render_admin_sso.py: {path}")

    def argocd(self):
        return yaml.safe_load(text("values.yaml"))

    def test_argocd_roles_follow_the_groups(self):
        csv = self.argocd()["configs"]["rbac"]["policy.csv"].splitlines()
        self.assertIn(f"g, {GROUPS['admin']}, role:admin", csv)
        for key in ("sre", "security", "engineering", "audit"):
            self.assertIn(f"g, {GROUPS[key]}, role:readonly", csv)
        self.assertNotIn(GROUPS["finance"], "\n".join(csv))
        self.assertEqual(self.argocd()["configs"]["rbac"]["policy.default"], "")

    def test_argocd_login_settings(self):
        values = self.argocd()
        cm = values["configs"]["cm"]
        self.assertEqual(cm["admin.enabled"], "false")
        oidc = yaml.safe_load(cm["oidc.config"])
        self.assertTrue(oidc["enablePKCEAuthentication"])
        self.assertEqual(oidc["clientID"], "$argocd-oidc:client_id")
        self.assertEqual(cm["url"], f"https://argocd.{CFG['dns']['admin_zone']}")
        secret = values["extraObjects"][0]
        self.assertEqual(secret["spec"]["target"]["template"]["metadata"]["labels"], {"app.kubernetes.io/part-of": "argocd"})
        self.assertEqual({d["remoteRef"]["key"] for d in secret["spec"]["data"]}, {"pay/shared-services/argocd/oidc"})

    def test_vault_policies_hide_secrets(self):
        self.assertRegex(text("admin.hcl"), r'path "secret/data/\*" \{\s+capabilities = \["deny"\]')
        self.assertRegex(text("readonly.hcl"), r'path "secret/\*" \{\s+capabilities = \["deny"\]')

    def test_vault_script(self):
        script = text("configure-oidc.sh")
        self.assertIn("set -euo pipefail", script)
        self.assertIn("--vault-addr", script)
        self.assertIn("--dry-run", script)
        self.assertIn('token_ttl: "1h"', script)
        self.assertIn(f'"{GROUPS["admin"]}=pay-oidc-admin"', script)
        self.assertNotIn(GROUPS["finance"], script)
        self.assertIn(f"https://vault.{CFG['dns']['admin_zone']}/ui/vault/auth/oidc/oidc/callback", script)

    def test_sentry_reads_the_client_from_its_secret(self):
        env = yaml.safe_load(text("oidc-values.yaml"))["sentry"]["web"]["env"]
        self.assertTrue(all(e["valueFrom"]["secretKeyRef"]["name"] == "sentry-oidc" for e in env if "valueFrom" in e))

    def test_no_secret_values(self):
        for body in OUT.values():
            self.assertNotRegex(body, r"(?i)client_secret\s*[:=]\s*[\"']?[A-Za-z0-9]{20,}")


if __name__ == "__main__":
    unittest.main()
