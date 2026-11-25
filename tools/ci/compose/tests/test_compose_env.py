import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import compose_env as ce  # noqa: E402

D = {s: "sha256:" + c * 64 for s, c in zip(ce.SERVICES, "abcd", strict=True)}
NEW = "sha256:" + "e" * 64


class ComposeEnvTest(unittest.TestCase):
    def files(self, digests, images):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "d.json").write_text(json.dumps(digests))
        (tmp / "i.yaml").write_text("images:\n" + "".join(f"  {k}: {v}\n" for k, v in images.items()))
        return str(tmp / "d.json"), str(tmp / "i.yaml")

    def run_main(self, *args):
        out = io.StringIO()
        return ce.main(list(args), out), out.getvalue()

    def test_built_digest_wins_over_the_running_one(self):
        d, i = self.files({"router": NEW}, D)
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i)
        self.assertEqual(code, 0)
        self.assertIn(f"ROUTER_IMAGE=r.example.com/pay/router@{NEW}", out)
        self.assertIn(f"LOCKER_IMAGE=r.example.com/pay/locker@{D['locker']}", out)

    def test_missing_service_fails(self):
        d, i = self.files({"router": NEW}, {})
        code, _ = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i)
        self.assertEqual(code, 1)

    def test_bad_artifact_values_are_ignored(self):
        d, i = self.files({"router": "latest", "evil": NEW}, D)
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i)
        self.assertEqual(code, 0)
        self.assertIn(f"router@{D['router']}", out)
        self.assertNotIn("EVIL", out)

    def test_keys_are_generated(self):
        d, i = self.files({}, D)
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i, "--keys")
        self.assertEqual(code, 0)
        self.assertRegex(out, r"ADMIN_API_KEY=[0-9a-f]{48}\n")

    def test_bad_registry_refused(self):
        self.assertEqual(self.run_main("--registry", "r.example.com/pay;rm")[0], 2)


if __name__ == "__main__":
    unittest.main()
