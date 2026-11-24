import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "buildkit"))
import buildkit_pin_check as bp  # noqa: E402

D = "sha256:" + "a" * 64


class BuildkitPinCheckTest(unittest.TestCase):
    def test_resolved_pin(self):
        self.assertEqual(bp.check(f"BUILDKIT_IMAGE=moby/buildkit:v0.23.2-rootless@{D}\n"), ([], []))

    def test_placeholder_is_unresolved_not_an_error(self):
        errors, unresolved = bp.check("BUILDKIT_IMAGE=moby/buildkit:v0.23.2-rootless@sha256:REPLACE_BUILDKIT_DIGEST\n")
        self.assertEqual((errors, len(unresolved)), ([], 1))

    def test_not_rootless_or_latest_or_bad_digest(self):
        self.assertTrue(bp.check(f"BUILDKIT_IMAGE=moby/buildkit:v0.23.2@{D}\n")[0])
        self.assertTrue(bp.check(f"BUILDKIT_IMAGE=moby/buildkit:latest-rootless@{D}\n")[0])
        self.assertTrue(bp.check("BUILDKIT_IMAGE=moby/buildkit:v1-rootless@sha256:abc\n")[0])
        self.assertTrue(bp.check("BUILDKIT_IMAGE=moby/buildkit:v1-rootless\n")[0])
        self.assertTrue(bp.check("# nothing\n")[0])

    def test_exit_codes(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / "buildkit.env"
            f.write_text("BUILDKIT_IMAGE=moby/buildkit:v1-rootless@sha256:REPLACE_X\n")
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(bp.main([str(f)]), 0)
                self.assertEqual(bp.main(["--strict", str(f)]), 1)
            self.assertIn("unresolved", out.getvalue())

    def test_repo_pin_is_well_formed(self):
        self.assertEqual(bp.check(bp.PIN.read_text())[0], [])


if __name__ == "__main__":
    unittest.main()
