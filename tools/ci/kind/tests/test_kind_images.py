import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import kind_images as ki  # noqa: E402

D = {s: "sha256:" + c * 64 for s, c in zip(ki.SERVICES, "abcdef", strict=True)}
NEW = "sha256:" + "9" * 64


class KindImagesTest(unittest.TestCase):
    def files(self, digests, images):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "d.json").write_text(json.dumps(digests))
        (tmp / "i.yaml").write_text("images:\n" + "".join(f"  {k}: {v}\n" for k, v in images.items()))
        return str(tmp / "d.json"), str(tmp / "i.yaml")

    def run_main(self, *args):
        out = io.StringIO()
        return ki.main(list(args), out), out.getvalue()

    def test_built_digest_wins_over_the_running_one(self):
        d, i = self.files({"router": NEW}, D)
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i)
        self.assertEqual(code, 0)
        first = out.splitlines()[0].split()
        self.assertEqual(first, ["router", f"r.example.com/pay/router@{NEW}", "pay.local/router", "9" * 16])
        self.assertEqual(len(out.splitlines()), len(ki.SERVICES))

    def test_values_name_the_local_images(self):
        d, i = self.files({}, D)
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i, "--values")
        self.assertEqual(code, 0)
        pairs = out.strip().split(",")
        self.assertIn("images.control-center.repository=pay.local/control-center", pairs)
        self.assertIn("images.smoke.tag=" + "f" * 16, pairs)
        self.assertEqual(len(pairs), 2 * len(ki.SERVICES))

    def test_missing_service_fails(self):
        d, i = self.files({}, {k: v for k, v in D.items() if k != "smoke"})
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i)
        self.assertEqual((code, out), (1, ""))

    def test_untrusted_artifact_entries_are_ignored(self):
        d, i = self.files({"router": "latest", "evil": NEW}, D)
        code, out = self.run_main("--registry", "r.example.com/pay", "--digests", d, "--images", i)
        self.assertEqual(code, 0)
        self.assertIn(f"router@{D['router']}", out)
        self.assertNotIn("evil", out)

    def test_bad_registry_is_refused(self):
        code, _ = self.run_main("--registry", "R.example.com/pay;rm")
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
