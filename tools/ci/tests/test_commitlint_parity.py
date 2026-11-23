"""commitlint (CI job `commitlint`) and tools/lint/spec-gate (commit-msg hook and CI) must accept and reject the same commit subjects.

Cases: every subject passed to `self.gate(...)` in tools/lint/tests/test_gate.py, the edge cases of commitlint-parity/subjects.txt and the
72 character limit. The real comparison needs commitlint: set COMMITLINT, put `commitlint` on PATH, or run in CI where npx may download it.
"""
import ast
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GATE = REPO / "tools" / "lint" / "spec-gate"
GATE_TESTS = REPO / "tools" / "lint" / "tests" / "test_gate.py"
CASES_FILE = Path(__file__).resolve().parent / "commitlint-parity" / "subjects.txt"
COMMITLINT_VERSION = "19.6.0"
PREFIX = "feat(infra): "


def literal(node):
    """Value of a string expression made only of constants (+ and *), or None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, (str, int)):
        return node.value
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mult)):
        left, right = literal(node.left), literal(node.right)
        if left is not None and right is not None:
            try:
                return left + right if isinstance(node.op, ast.Add) else left * right
            except TypeError:
                return None
    return None


def gate_test_subjects():
    """First line of every message that test_gate.py feeds to the gate."""
    found = []
    for node in ast.walk(ast.parse(GATE_TESTS.read_text(encoding="utf-8"))):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "gate" and node.args:
            value = literal(node.args[0])
            if isinstance(value, str) and value.strip():
                found.append(value.splitlines()[0])
    return found


def edge_cases():
    lines = [x.rstrip("\n") for x in CASES_FILE.read_text(encoding="utf-8").splitlines() if x.strip() and not x.startswith("#")]
    return lines + [PREFIX + "a" * (72 - len(PREFIX)), PREFIX + "a" * (73 - len(PREFIX))]


def all_cases():
    return list(dict.fromkeys(gate_test_subjects() + edge_cases()))


def mismatches(cases, accepts_a, accepts_b):
    """Subjects that one validator accepts and the other rejects."""
    return [(s, accepts_a(s), accepts_b(s)) for s in cases if accepts_a(s) != accepts_b(s)]


class Gate:
    """spec-gate on a message that changes only an exempt file, so that only the subject rules decide."""

    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="parity-"))
        (self.root / "policy").mkdir()
        shutil.copy(REPO / "policy" / "cde-paths.yaml", self.root / "policy" / "cde-paths.yaml")
        (self.root / "README.md").write_text("x", encoding="utf-8")
        for args in (["init", "-q", "-b", "main"], ["add", "README.md"]):
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def close(self):
        shutil.rmtree(self.root, True)

    def accepts(self, subject):
        msg = self.root / "MSG"
        msg.write_text(subject + "\n", encoding="utf-8")
        p = subprocess.run([sys.executable, str(GATE), "--msg", str(msg)], cwd=self.root, capture_output=True, text=True,
                           env=dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root)))
        return p.returncode == 0


def commitlint_command():
    if os.environ.get("COMMITLINT"):
        return os.environ["COMMITLINT"].split()
    if shutil.which("commitlint"):
        return ["commitlint"]
    if os.environ.get("CI") and shutil.which("npx"):
        return ["npx", "--yes", f"@commitlint/cli@{COMMITLINT_VERSION}"]
    return None


def commitlint_accepts(command):
    def accepts(subject):
        p = subprocess.run([*command, "--config", str(REPO / "commitlint.config.js")], input=subject + "\n", cwd=REPO, capture_output=True, text=True)
        return p.returncode == 0
    return accepts


class ComparatorTest(unittest.TestCase):
    """The comparison itself, without commitlint: a deliberately mismatched case must be reported."""

    def test_agreeing_validators_have_no_mismatch(self):
        self.assertEqual(mismatches(["a", "b"], lambda s: s == "a", lambda s: s == "a"), [])

    def test_a_deliberately_mismatched_case_fails(self):
        self.assertEqual(mismatches(["a", "b"], lambda s: True, lambda s: s == "a"), [("b", True, False)])

    def test_cases_include_the_gate_tests_and_the_length_limit(self):
        cases = all_cases()
        for expected in ("fixed things", "feat(nope): add it", "docs(docs): Update readme", "docs(docs): update readme", "docs(docs): " + "a" * 70):
            self.assertIn(expected, cases)
        self.assertEqual({len(s) for s in cases if s.startswith(PREFIX + "a")} & {72, 73}, {72, 73})


class ParityTest(unittest.TestCase):
    def test_gate_and_commitlint_agree_on_every_subject(self):
        command = commitlint_command()
        if command is None:
            self.skipTest("commitlint is not available: set COMMITLINT or install @commitlint/cli")
        gate = Gate()
        self.addCleanup(gate.close)
        found = mismatches(all_cases(), gate.accepts, commitlint_accepts(command))
        self.assertEqual(found, [], "subject, spec-gate accepts, commitlint accepts")


if __name__ == "__main__":
    unittest.main()
