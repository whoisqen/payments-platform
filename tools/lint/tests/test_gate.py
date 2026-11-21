"""Tests for tools/lint/spec-gate (commit format and the link to an approved specification task)."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GATE = REPO / "tools" / "lint" / "spec-gate"
TASKS = '# Tasks\n\n```yaml\n- id: T1\n  agent: terraform-engineer\n  paths: ["infra/modules/x/**"]\n  issue: "#2"\n```\n'


PROGRESS = '---\ntask: T1\nissue: "#2"\nstatus: in-progress\nagent: terraform-engineer\npr: none\n---\n'


def spec_md(status):
    return f"---\nid: 001-x\nstatus: {status}\n---\n\n# 001-x: X\n"


class GateTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="gate-test-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        (self.root / "policy").mkdir()
        shutil.copy(REPO / "policy" / "cde-paths.yaml", self.root / "policy" / "cde-paths.yaml")
        self.git("init", "-q", "-b", "main")

    def git(self, *a):
        return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=self.root,
                              capture_output=True, text=True, check=True).stdout

    def write(self, rel, text="x"):
        f = self.root / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text, encoding="utf-8")
        self.git("add", rel)

    def gate(self, msg):
        m = self.root / "MSG"
        m.write_text(msg, encoding="utf-8")
        p = subprocess.run([sys.executable, str(GATE), "--msg", str(m)], cwd=self.root, capture_output=True, text=True,
                           env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
        return p.returncode, p.stderr

    def approved_spec(self, status="approved"):
        self.write("specs/001-x/spec.md", spec_md(status))
        self.write("specs/001-x/tasks.md", TASKS)
        self.write("specs/001-x/progress/T1.md", PROGRESS)
        self.git("commit", "-q", "-m", "docs(specs): add spec")

    def test_bad_subject(self):
        self.write("README.md")
        self.assertEqual(self.gate("fixed things")[0], 1)
        self.assertEqual(self.gate("feat(nope): add it")[0], 1)

    def test_summary_must_start_lower_case(self):
        self.write("README.md")
        self.assertEqual(self.gate("docs(docs): Update readme")[0], 1)
        self.assertEqual(self.gate("docs(docs): update readme")[0], 0)

    def test_long_subject(self):
        self.write("README.md")
        self.assertEqual(self.gate("docs(docs): " + "a" * 70)[0], 1)

    def test_ai_mark(self):
        self.write("README.md")
        self.assertEqual(self.gate("docs(docs): ok\n\nCo-Authored-By: Claude <noreply@anthropic.com>")[0], 1)

    def test_exempt_file_needs_no_spec(self):
        self.write("README.md")
        self.assertEqual(self.gate("docs(docs): update readme")[0], 0)

    def test_draft_spec_files_need_no_trailer(self):
        self.write("specs/001-x/spec.md", spec_md("draft"))
        self.write("specs/001-x/tasks.md", TASKS)
        self.assertEqual(self.gate("docs(specs): add draft spec")[0], 0)

    def test_in_progress_spec_files_are_human_edited(self):
        self.write("specs/001-x/spec.md", spec_md("in-progress"))
        self.assertEqual(self.gate("docs(specs): edit spec")[0], 0)

    def test_implemented_spec_files_are_frozen(self):
        self.write("specs/001-x/spec.md", spec_md("implemented"))
        self.assertEqual(self.gate("docs(specs): edit spec")[0], 1)

    def test_human_only_tooling_needs_no_spec(self):
        self.write("tools/lint/new-lint")
        self.assertEqual(self.gate("feat(ci): add lint")[0], 0)

    def test_gated_file_needs_spec_trailer(self):
        self.write("infra/modules/x/main.tf")
        self.assertEqual(self.gate("feat(infra): add module")[0], 1)

    def test_draft_spec_rejected(self):
        self.approved_spec("draft")
        self.write("infra/modules/x/main.tf")
        code, err = self.gate("feat(infra): add module\n\nSpec: specs/001-x#T1")
        self.assertEqual(code, 1)
        self.assertIn("must be approved", err)

    def test_approved_spec_and_task_paths(self):
        self.approved_spec()
        self.write("infra/modules/x/main.tf")
        self.assertEqual(self.gate("feat(infra): add module\n\nSpec: specs/001-x#T1")[0], 0)
        self.write("infra/modules/y/main.tf")
        code, err = self.gate("feat(infra): add module\n\nSpec: specs/001-x#T1")
        self.assertEqual(code, 1)
        self.assertIn("outside the paths", err)

    def test_task_without_issue_rejected(self):
        self.approved_spec()
        (self.root / "specs/001-x/tasks.md").write_text(TASKS.replace('"#2"', "none"), encoding="utf-8")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "docs(specs): fix tasks")
        self.write("infra/modules/x/main.tf")
        code, err = self.gate("feat(infra): add module\n\nSpec: specs/001-x#T1")
        self.assertEqual(code, 1)
        self.assertIn("no GitHub issue yet", err)

    def test_task_must_be_in_progress(self):
        self.approved_spec()
        self.write("specs/001-x/progress/T1.md", PROGRESS.replace("in-progress", "todo"))
        self.git("commit", "-q", "-m", "docs(specs): todo")
        self.write("infra/modules/x/main.tf")
        code, err = self.gate("feat(infra): add module\n\nSpec: specs/001-x#T1")
        self.assertEqual(code, 1)
        self.assertIn("not in-progress", err)

    def test_owner_directed_exemption(self):
        self.write("infra/a.tf")
        self.assertEqual(self.gate("feat(infra): add a\n\nSpec: none\nSpec-Exempt: owner-directed")[0], 0)

    def test_unknown_task(self):
        self.approved_spec()
        self.write("infra/modules/x/main.tf")
        self.assertEqual(self.gate("feat(infra): add module\n\nSpec: specs/001-x#T9")[0], 1)

    def test_bootstrap_only_before_first_spec(self):
        self.write("tools/a.py")
        msg = "feat(ci): add tool\n\nSpec: none\nSpec-Exempt: bootstrap"
        self.assertEqual(self.gate(msg)[0], 0)
        self.git("commit", "-q", "-m", "feat(ci): add tool")
        self.approved_spec()
        self.write("tools/b.py")
        self.assertEqual(self.gate(msg)[0], 1)

    def test_upstream_import_only_for_vendor(self):
        self.write("vendor/hyperswitch/Cargo.toml")
        ok = "chore(vendor): import upstream\n\nSpec: none\nSpec-Exempt: upstream-import"
        self.assertEqual(self.gate(ok)[0], 0)
        self.write("infra/a.tf")
        self.assertEqual(self.gate(ok)[0], 1)

    def test_cde_path_needs_pci_trailer(self):
        self.write("vendor/card-vault/src/main.rs")
        base = "chore(vendor): import upstream\n\nSpec: none\nSpec-Exempt: upstream-import"
        self.assertEqual(self.gate(base)[0], 1)
        self.assertEqual(self.gate(base + "\nPCI-Impact: none")[0], 0)

    def test_range_mode(self):
        self.write("README.md")
        self.git("commit", "-q", "-m", "docs(docs): readme")
        self.write("infra/a.tf")
        self.git("commit", "-q", "-m", "feat(infra): no spec")
        p = subprocess.run([sys.executable, str(GATE), "--range", "HEAD~1..HEAD"], cwd=self.root, capture_output=True,
                           text=True, env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
        self.assertEqual(p.returncode, 1)
        self.assertIn("Spec: specs/NNN-slug#Tn", p.stderr)


if __name__ == "__main__":
    unittest.main()
