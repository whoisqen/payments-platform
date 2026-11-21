"""Tests for tools/lint/srs-lint (requirement IDs and addenda) and the baseline rule of spec-gate."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
LINT = REPO / "tools" / "lint" / "srs-lint"
GATE = REPO / "tools" / "lint" / "spec-gate"
HEAD = "| ID | Requirement | Verification | Implementation | Source |\n|---|---|---|---|---|\n"
FM = "---\nstatus: baseline\n---\n\n"


def req(rid, text="The platform shall do x.", ver="test", src="s3"):
    return f"| {rid} | {text} | {ver} | Terraform module | {src} |\n"


class SrsTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="srs-test-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "docs" / "requirements" / "addenda").mkdir(parents=True)
        (self.root / "specs" / "001-x").mkdir(parents=True)
        (self.root / "specs" / "001-x" / "spec.md").write_text("---\nstatus: approved\n---\n", encoding="utf-8")
        (self.root / "policy").mkdir()
        shutil.copy(REPO / "policy" / "cde-paths.yaml", self.root / "policy" / "cde-paths.yaml")

    def w(self, rel, text):
        f = self.root / "docs" / "requirements" / rel
        f.write_text(text, encoding="utf-8")

    def lint(self, *a):
        p = subprocess.run([sys.executable, str(LINT), *a], cwd=self.root, capture_output=True, text=True,
                           env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
        return p.returncode, p.stdout

    def addendum(self, name="001-a", status="approved", body=""):
        self.w(f"addenda/{name}.md", f"---\nid: {name}\nstatus: {status}\nspec: specs/001-x\n---\n\n# A\n\n{body}")

    def test_valid_baseline(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1") + req("NFR-INF-2", ver="metric"))
        self.assertEqual(self.lint()[0], 0)

    def test_duplicate_and_malformed(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1") + req("FR-INF-1") + req("FR-inf-3"))
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("already defined", out)
        self.assertIn("malformed ID", out)

    def test_length_limit(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1", text="The platform shall " + "x" * 400))
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("limited to 400", out)

    def test_requirement_rules(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1", text="Something.") + req("FR-INF-2", ver="vibes"))
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("`shall` statement", out)
        self.assertIn("verification must be", out)

    def test_addendum_adds_and_changes(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        self.addendum(body="## Added\n\n" + HEAD + req("FR-INF-2") + "\n## Changed\n\n" + HEAD + req("FR-INF-1", "The platform shall do y."))
        code, out = self.lint("--effective")
        self.assertEqual(code, 0, out)
        self.assertIn("FR-INF-2 001-a.md", out)

    def test_addendum_cannot_reuse_or_change_unknown(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        self.addendum(body="## Added\n\n" + HEAD + req("FR-INF-1") + "\n## Changed\n\n" + HEAD + req("FR-INF-9"))
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("never reused", out)
        self.assertIn("does not exist", out)

    def test_withdrawn_id_is_not_reusable(self):
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        self.addendum("001-a", body="## Withdrawn\n\n| ID | Reason |\n|---|---|\n| FR-INF-1 | obsolete |\n")
        self.addendum("002-b", body="## Added\n\n" + HEAD + req("FR-INF-1"))
        code, out = self.lint("--effective")
        self.assertEqual(code, 1)
        self.assertNotIn("FR-INF-1 a.md", out)

    def test_addendum_needs_spec_and_rows(self):
        self.addendum(body="nothing here")
        shutil.rmtree(self.root / "specs" / "001-x")
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("existing specs/NNN-slug", out)
        self.assertIn("at least one", out)

    def test_live_addendum_needs_approved_spec(self):
        (self.root / "specs" / "001-x" / "spec.md").write_text("---\nstatus: draft\n---\n", encoding="utf-8")
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        self.addendum(body="## Added\n\n" + HEAD + req("FR-INF-2"))
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("needs its specification", out)
        (self.root / "specs" / "001-x" / "spec.md").write_text("---\nstatus: approved\n---\n", encoding="utf-8")
        self.assertEqual(self.lint()[0], 0)

    def spec(self, n, status, text="", extra=""):
        d = self.root / "specs" / n
        d.mkdir(exist_ok=True)
        (d / "spec.md").write_text(f"---\nstatus: {status}\n{extra}---\n\n{text}\n", encoding="utf-8")

    def changing_addendum(self, extra_fm=""):
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        self.w("addenda/001-a.md", f"---\nid: 001-a\nstatus: approved\nspec: specs/001-x\n{extra_fm}---\n\n## Changed\n\n" + HEAD + req("FR-INF-1", "The platform shall do y."))

    def test_revalidation_of_approved_spec(self):
        self.spec("002-y", "approved", "AC cites FR-INF-1")
        self.changing_addendum()
        code, out = self.lint()
        self.assertEqual(code, 1)
        self.assertIn("re-validate", out)
        self.spec("002-y", "approved", "AC cites FR-INF-1", "revalidated: [001-a]\n")
        self.assertEqual(self.lint()[0], 0)

    def test_implemented_spec_needs_follow_up(self):
        self.spec("002-y", "implemented", "AC cites FR-INF-1")
        self.changing_addendum()
        self.assertEqual(self.lint()[0], 1)
        self.spec("003-z", "draft", "follow-up")
        self.changing_addendum("follow-up: specs/003-z\n")
        self.assertEqual(self.lint()[0], 0)

    def test_unrelated_and_draft_specs_are_ignored(self):
        self.spec("002-y", "approved", "cites FR-INF-7")
        self.spec("003-z", "draft", "cites FR-INF-1")
        self.changing_addendum()
        self.assertEqual(self.lint()[0], 0)

    def test_gate_rejects_addendum_when_revalidation_is_missing(self):
        run = lambda *a: subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=self.root,
                                        capture_output=True, text=True, check=True)
        run("init", "-q", "-b", "main")
        self.spec("002-y", "approved", "AC cites FR-INF-1")
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        run("add", ".")
        run("commit", "-q", "-m", "docs(docs): baseline")
        (self.root / "specs" / "001-x" / "tasks.md").write_text("```yaml\n- id: T1\n  paths: [\"docs/requirements/addenda/**\"]\n```\n", encoding="utf-8")
        run("add", ".")
        run("commit", "-q", "-m", "docs(specs): add tasks")
        self.changing_addendum()
        run("add", ".")
        m = self.root / "MSG"
        m.write_text("docs(docs): change requirement\n\nSpec: specs/001-x#T1", encoding="utf-8")
        p = subprocess.run([sys.executable, str(GATE), "--msg", str(m)], cwd=self.root, capture_output=True, text=True,
                           env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
        self.assertEqual(p.returncode, 1)
        self.assertIn("re-validate", p.stderr)

    def test_gate_rejects_addendum_without_own_spec(self):
        run = lambda *a: subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=self.root,
                                        capture_output=True, text=True, check=True)
        run("init", "-q", "-b", "main")
        self.addendum("001-a", "draft", "## Added\n\n" + HEAD + req("FR-INF-2"))
        run("add", ".")
        m = self.root / "MSG"
        for trailer, ok in (("Spec: none\nSpec-Exempt: bootstrap", 1), ("Spec: specs/002-y#T1", 1)):
            m.write_text("docs(docs): add addendum\n\n" + trailer, encoding="utf-8")
            p = subprocess.run([sys.executable, str(GATE), "--msg", str(m)], cwd=self.root, capture_output=True,
                               text=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
            self.assertEqual(p.returncode, ok)
            self.assertIn("never exempt", p.stderr)

    def test_gate_rejects_baseline_edit(self):
        run = lambda *a: subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=self.root,
                                        capture_output=True, text=True, check=True)
        run("init", "-q", "-b", "main")
        self.w("a.md", FM + HEAD + req("FR-INF-1"))
        run("add", ".")
        run("commit", "-q", "-m", "docs(docs): baseline")
        self.w("a.md", FM + HEAD + req("FR-INF-1", "The platform shall do z."))
        run("add", ".")
        m = self.root / "MSG"
        m.write_text("docs(docs): edit\n\nSpec: none\nSpec-Exempt: bootstrap", encoding="utf-8")
        p = subprocess.run([sys.executable, str(GATE), "--msg", str(m)], cwd=self.root, capture_output=True, text=True,
                           env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
        self.assertEqual(p.returncode, 1)
        self.assertIn("is a baseline", p.stderr)


if __name__ == "__main__":
    unittest.main()
