import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import first_release as fr  # noqa: E402

D1, D2, D3 = ("sha256:" + c * 64 for c in "abc")


class DecideTest(unittest.TestCase):
    def test_first_release_is_v0_1_0(self):
        self.assertEqual(fr.decide([], {"router": D1}, {D1, D2}, True), {"version": "v0.1.0", "bump": "first"})

    def test_existing_tag_fails_or_is_a_no_op(self):
        with self.assertRaises(fr.FirstReleaseError):
            fr.decide(["v0.1.0"], {"router": D1}, {D1}, True)
        self.assertEqual(fr.decide(["v1.2.0"], {}, set(), False, only_if_first=True)["bump"], "none")

    def test_guards(self):
        for args in (([], {"router": D1}, {D1}, False), ([], {}, {D1}, True), ([], {"router": D1, "locker": D3}, {D1}, True)):
            with self.assertRaises(fr.FirstReleaseError, msg=args):
                fr.decide(*args)


class GitTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "user.name", "ci")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, capture_output=True, text=True, check=True).stdout.strip()

    def commit(self, env, digest):
        p = self.repo / f"deploy/envs/{env}/images.yaml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(f"images:\n  router: {digest}\n", encoding="utf-8")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", f"chore(deploy): promote {env}")
        return self.git("rev-parse", "HEAD")

    def run_tool(self, *args):
        out = subprocess.run([sys.executable, str(HERE / "first_release.py"), *args], cwd=self.repo,
                             capture_output=True, text=True, env={**os.environ, "GIT_DIR": str(self.repo / ".git")})
        return out.returncode, out.stdout

    def test_stage_verified_digest_gets_v0_1_0_once(self):
        self.commit("stage", D1)
        self.commit("stage", D2)
        sha = self.commit("prod", D1)
        code, out = self.run_tool("--sha", sha, "--main", "main", "--changelog-out", str(self.repo / "notes.md"))
        self.assertEqual(code, 0, out)
        self.assertEqual(json.loads(out)["version"], "v0.1.0")
        self.assertIn(D1, (self.repo / "notes.md").read_text())
        self.git("tag", "v0.1.0", sha)
        self.assertEqual(json.loads(self.run_tool("--sha", sha, "--main", "main", "--if-first")[1])["bump"], "none")
        self.assertEqual(self.run_tool("--sha", sha, "--main", "main")[0], 1)

    def test_digest_that_skipped_stage_is_refused(self):
        self.commit("stage", D1)
        sha = self.commit("prod", D3)
        self.assertEqual(self.run_tool("--sha", sha, "--main", "main")[0], 1)


if __name__ == "__main__":
    unittest.main()
