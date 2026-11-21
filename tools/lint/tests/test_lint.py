"""Tests for tools/lint/spec-lint and tools/lint/orchestration-lint.

Each test builds a throwaway project root in a temp directory and runs the linters against it
through CLAUDE_PROJECT_DIR, so the real specs/ directory is never touched.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SPEC_LINT = REPO / "tools" / "lint" / "spec-lint"
ORCH_LINT = REPO / "tools" / "lint" / "orchestration-lint"

SPEC = """---
id: {n}
status: draft
owner: platform
milestone: {n}
issue: "#1"
pci-impact: {pci}
adr: {adr}
---

# {n}: Example change

## Problem

The example module and chart do not exist, so the example workload cannot be deployed.

## Goals and non-goals

- Goal: add the example module and its chart.
- Non-goal: live configuration and environment values.

## Acceptance criteria

{criteria}

## Impact on SLO, PCI and cost

- SLO: none, the workload is not on the payment path.
- PCI: none, no access to the CDE and no keys.
- Cost: about 10 USD a month in dev.

## Risks

- The output is missing in the chart values; the chart fails to render.
"""
PLAN = """# Plan: {n}

## Components and boundaries

The module output feeds the chart.

## Changes per domain

- infra: the module; Helm: the chart.

## ADRs

Not needed: no architecture decision changes.

## Rollout and rollback

Promote dev, then stage; revert the commit to roll back.

## Test plan

terraform test and helm lint.

## Alerts and dashboards

None: the workload is not on the payment path.
"""

TASKS = """# Tasks: {n}

```yaml
{tasks}
```
"""
T1 = """- id: T1
  title: Add module
  agent: terraform-engineer
  paths: ["infra/modules/example/**"]
  depends_on: []
  provides: output example_arn
  requires: []
  acceptance: terraform test passes
  issue: "#2"
"""
T2 = """- id: T2
  title: Add chart
  agent: k8s-engineer
  paths: ["deploy/charts/example/**"]
  depends_on: [T1]
  provides: chart example
  requires: ["output example_arn"]
  acceptance: helm lint passes
  issue: "#3"
"""
INDEX_HEAD = "| Number | Title | Status | Milestone |\n|---|---|---|---|\n"


def make_root():
    root = Path(tempfile.mkdtemp(prefix="lint-test-"))
    (root / ".claude").mkdir()
    shutil.copy(REPO / ".claude" / "orchestration.yaml", root / ".claude" / "orchestration.yaml")
    shutil.copytree(REPO / ".claude" / "agents", root / ".claude" / "agents")
    shutil.copytree(REPO / ".claude" / "commands", root / ".claude" / "commands")
    (root / "policy").mkdir()
    shutil.copy(REPO / "policy" / "cde-paths.yaml", root / "policy" / "cde-paths.yaml")
    (root / "docs" / "adr").mkdir(parents=True)
    shutil.copy(REPO / "docs" / "glossary.md", root / "docs" / "glossary.md")
    (root / "docs" / "adr" / "0016-hot-merchant.md").write_text("# ADR 0016\n", encoding="utf-8")
    (root / "specs").mkdir()
    (root / "specs" / "README.md").write_text("# specs\n\n" + INDEX_HEAD, encoding="utf-8")
    return root


def write_spec(root, n="001", pci="none", adr="[]", criteria="- [ ] terraform test passes in CI", tasks=None,
               plan=None, spec=None, index=True):
    d = root / "specs" / f"{n}-example"
    d.mkdir(parents=True, exist_ok=True)
    name = f"{n}-example"
    (d / "spec.md").write_text((spec or SPEC).format(n=name, pci=pci, adr=adr, criteria=criteria), encoding="utf-8")
    (d / "plan.md").write_text((plan or PLAN).format(n=name), encoding="utf-8")
    (d / "tasks.md").write_text(TASKS.format(n=name, tasks=(tasks or T1 + T2).rstrip("\n")), encoding="utf-8")
    if index:
        write_index(root)
    return d


def write_index(root):
    rows = ""
    for d in sorted((root / "specs").glob("[0-9][0-9][0-9]-*")):
        rows += f"| {d.name[:3]} | Example change | draft | {d.name} |\n"
    (root / "specs" / "README.md").write_text("# specs\n\n" + INDEX_HEAD + rows, encoding="utf-8")


def run(script, root, *args):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))
    p = subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True, env=env, cwd=root)
    return p.returncode, p.stdout + p.stderr


class SpecLintTest(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.addCleanup(shutil.rmtree, self.root, True)

    def fails(self, text, *args):
        code, out = run(SPEC_LINT, self.root, *args)
        self.assertEqual(code, 1, out)
        self.assertIn(text, out)

    def test_valid_spec_passes(self):
        write_spec(self.root)
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)
        self.assertIn("0 error(s)", out)

    def test_no_specs_passes(self):
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_missing_spec_section(self):
        write_spec(self.root, spec=SPEC[: SPEC.index("## Risks")])
        self.fails("lacks section `## Risks`")

    def test_empty_section_rejected(self):
        write_spec(self.root, spec=SPEC.replace("- The output is missing in the chart values; the chart fails to render.", ""))
        self.fails("section `## Risks` is empty")

    def test_missing_non_goal_rejected(self):
        write_spec(self.root, spec=SPEC.replace("- Non-goal: live configuration and environment values.", ""))
        self.fails("needs a `Non-goal:` line")

    def test_requires_without_depends_on_rejected(self):
        write_spec(self.root, tasks=T1 + T2.replace("depends_on: [T1]", "depends_on: []"))
        self.fails("does not depend on the task that provides it")

    def test_prod_path_rejected(self):
        write_spec(self.root, tasks=T1 + T2.replace("deploy/charts/example/**", "deploy/envs/prod/euw1/cell-1/**"))
        self.fails("denied for agents")

    def test_zero_issue_rejected(self):
        write_spec(self.root, spec=SPEC.replace('issue: "#1"', 'issue: "#0"'))
        self.fails('issue must look like "#123"')

    def test_draft_without_plan_passes(self):
        d = write_spec(self.root)
        (d / "plan.md").unlink()
        (d / "tasks.md").unlink()
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_block_list_depends_on_is_parsed(self):
        t2 = T2.replace("depends_on: [T1]", "depends_on:\n    - T1")
        write_spec(self.root, tasks=T1 + t2)
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_block_list_requires_unknown_provider_rejected(self):
        t2 = T2.replace('requires: ["output example_arn"]', "requires:\n    - nothing")
        write_spec(self.root, tasks=T1 + t2)
        self.fails("requires `nothing` but no task provides it")

    def test_bad_directory_name_rejected(self):
        write_spec(self.root)
        (self.root / "specs" / "01-x").mkdir()
        self.fails("must be named NNN-kebab-case")

    def test_compound_name_is_not_a_glossary_hit(self):
        write_spec(self.root, spec=SPEC.replace("do not exist", "do not exist; see obs-gateway"))
        code, out = run(SPEC_LINT, self.root)
        self.assertNotIn("gateway", out)

    def test_issue_none_only_before_work_starts(self):
        write_spec(self.root, spec=SPEC.replace('issue: "#1"', "issue: none"), tasks=(T1 + T2).replace('"#2"', "none").replace('"#3"', "none"))
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)
        write_spec(self.root, spec=SPEC.replace("status: draft", "status: in-progress").replace('issue: "#1"', "issue: none"))
        self.fails('issue must look like "#123"')

    def progress(self, d, tid, **kw):
        f = {"task": tid, "issue": '"#2"', "status": "in-progress", "agent": "terraform-engineer", "pr": "none"}
        f.update(kw)
        (d / "progress").mkdir(exist_ok=True)
        (d / "progress" / f"{tid}.md").write_text("---\n" + "".join(f"{k}: {v}\n" for k, v in f.items()) + "---\n", encoding="utf-8")

    def started(self):
        d = write_spec(self.root, spec=SPEC.replace("status: draft", "status: in-progress"))
        r = self.root / "specs" / "README.md"
        r.write_text(r.read_text(encoding="utf-8").replace("| draft |", "| in-progress |"), encoding="utf-8")
        return d

    def test_progress_rules(self):
        d = self.started()
        self.progress(d, "T1")
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)
        self.progress(d, "T1", status="done")
        self.fails("must name its pull request")
        self.progress(d, "T1", status="done", pr="#7")
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_progress_respects_dependencies_and_agent(self):
        d = self.started()
        self.progress(d, "T2", agent="k8s-engineer", issue='"#3"')
        self.fails("depends on T1, which is not done")
        self.progress(d, "T1", status="done", pr="#7")
        self.progress(d, "T2", agent="docs-writer", issue='"#3"')
        self.fails("`agent` must be the task agent")

    def test_progress_issue_must_match(self):
        d = self.started()
        self.progress(d, "T1", issue='"#9"')
        self.fails("`issue` must equal")

    def test_bad_status(self):
        write_spec(self.root, spec=SPEC.replace("status: draft", "status: done"))
        self.fails("status must be one of")

    def test_id_mismatch(self):
        d = write_spec(self.root)
        t = (d / "spec.md").read_text(encoding="utf-8").replace("id: 001-example", "id: 009-other", 1)
        (d / "spec.md").write_text(t, encoding="utf-8")
        self.fails("must equal the directory name")

    def test_number_gap(self):
        write_spec(self.root, "001")
        write_spec(self.root, "003")
        self.fails("without gaps or repeats")

    def test_empty_acceptance_criteria(self):
        write_spec(self.root, criteria="")
        self.fails("acceptance criteria are empty")

    def test_plan_missing_section(self):
        write_spec(self.root, plan=PLAN.replace("## Test plan\n\n", ""))
        self.fails("plan.md lacks section `## Test plan`")

    def test_unknown_agent(self):
        write_spec(self.root, tasks=T1.replace("terraform-engineer", "magic-engineer"))
        self.fails("unknown agent `magic-engineer`")

    def test_path_outside_owns(self):
        write_spec(self.root, tasks=T1.replace("infra/modules/example/**", "deploy/charts/x/**"))
        self.fails("is outside the owns of terraform-engineer")

    def test_ci_only_path_rejected(self):
        t = T2.replace("deploy/charts/example/**", "deploy/envs/prod/images.yaml").replace("depends_on: [T1]", "depends_on: []")
        t = t.replace('requires: ["output example_arn"]', "requires: []")
        write_spec(self.root, tasks=t)
        self.fails("ci_only files")

    def test_dependency_cycle(self):
        t1 = T1.replace("depends_on: []", "depends_on: [T2]")
        write_spec(self.root, tasks=t1 + T2)
        self.fails("depends_on cycle")

    def test_unknown_dependency(self):
        write_spec(self.root, tasks=T1.replace("depends_on: []", "depends_on: [T9]"))
        self.fails("unknown task `T9`")

    def test_requires_without_provides(self):
        write_spec(self.root, tasks=T1 + T2.replace("output example_arn", "output missing"))
        self.fails("requires `output missing` but no task provides it")

    def test_bad_task_issue(self):
        write_spec(self.root, tasks=T1.replace('issue: "#2"', "issue: two"))
        self.fails("issue must look like")

    def test_duplicate_task_ids(self):
        write_spec(self.root, tasks=T1 + T1)
        self.fails("task ids are not unique")

    def test_cde_path_needs_pci_impact_yes(self):
        t = T1.replace("terraform-engineer", "rust-engineer").replace("infra/modules/example/**", "vendor/hyperswitch/crates/router/src/x/**")
        write_spec(self.root, tasks=t)
        self.fails("touches a CDE path but pci-impact is not `yes`")

    def test_cde_path_with_pci_impact_yes_passes(self):
        t = T1.replace("terraform-engineer", "rust-engineer").replace("infra/modules/example/**", "vendor/hyperswitch/crates/router/src/x/**")
        write_spec(self.root, pci="yes", tasks=t)
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_overlapping_paths_need_ordering(self):
        t2 = T2.replace("deploy/charts/example/**", "infra/modules/example/sub/**").replace("k8s-engineer", "terraform-engineer")
        t2 = t2.replace("depends_on: [T1]", "depends_on: []")
        write_spec(self.root, tasks=T1 + t2)
        self.fails("overlapping paths and no depends_on")

    def test_overlapping_paths_with_ordering_pass(self):
        t2 = T2.replace("deploy/charts/example/**", "infra/modules/example/sub/**").replace("k8s-engineer", "terraform-engineer")
        write_spec(self.root, tasks=T1 + t2)
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_apply_task_rejected(self):
        write_spec(self.root, tasks=T1.replace("terraform test passes", "terraform apply succeeds"))
        self.fails("agents never apply")

    def test_missing_adr(self):
        write_spec(self.root, adr="[0099]")
        self.fails("adr `0099` has no docs/adr/0099-*.md")

    def test_existing_adr_passes(self):
        write_spec(self.root, adr="[0016]")
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_handoff_naming(self):
        d = write_spec(self.root)
        (d / "handoffs").mkdir()
        (d / "handoffs" / "notes.md").write_text("x", encoding="utf-8")
        self.fails("handoff `notes.md` must be named")
        (d / "handoffs" / "notes.md").unlink()
        (d / "handoffs" / "terraform-engineer-k8s-engineer.md").write_text("x", encoding="utf-8")
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)

    def test_index_out_of_date_and_rewrite(self):
        write_spec(self.root, index=False)
        self.fails("index is out of date")
        code, out = run(SPEC_LINT, self.root, "--write-index")
        self.assertEqual(code, 0, out)
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)
        self.assertIn("| 001 | Example change | draft | 001-example |", (self.root / "specs" / "README.md").read_text(encoding="utf-8"))

    def test_glossary_term_warns_but_does_not_fail(self):
        write_spec(self.root, spec=SPEC.replace("The example module and chart do not exist", "Every transaction is lost. The example module and chart do not exist"))
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)
        self.assertRegex(out, r"warning: .*spec\.md uses `transaction`")


    def test_glossary_ignores_code_and_paths(self):
        write_spec(self.root, tasks=T1.replace("Add module", "Add module under infra") + T2)
        code, out = run(SPEC_LINT, self.root)
        self.assertEqual(code, 0, out)
        self.assertNotIn("`deploy`", out)


class OrchestrationLintTest(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.addCleanup(shutil.rmtree, self.root, True)

    def test_real_definitions_have_no_errors(self):
        code, out = run(ORCH_LINT, self.root)
        self.assertEqual(code, 0, out)
        self.assertIn("0 error(s)", out)

    def test_reviewer_with_edit_is_rejected(self):
        p = self.root / ".claude" / "agents" / "review" / "pci-auditor.md"
        p.write_text(p.read_text(encoding="utf-8").replace("tools: Read, Grep, Glob", "tools: Read, Edit, Grep"), encoding="utf-8")
        code, out = run(ORCH_LINT, self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("reviewers may only use", out)

    def test_wrong_model_is_rejected(self):
        p = self.root / ".claude" / "agents" / "implement" / "ci-engineer.md"
        p.write_text(p.read_text(encoding="utf-8").replace("model: sonnet", "model: opus"), encoding="utf-8")
        code, out = run(ORCH_LINT, self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("model must be sonnet", out)

    def test_pipeline_agent_without_definition_is_rejected(self):
        (self.root / ".claude" / "agents" / "review" / "spec-reviewer.md").unlink()
        code, out = run(ORCH_LINT, self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("pipeline references agent `spec-reviewer`", out)

    def test_overlapping_owns_is_rejected(self):
        p = self.root / ".claude" / "orchestration.yaml"
        t = re.sub(r'terraform-engineer:(\s+)\{ owns: \["infra/\*\*"\] \}', r'terraform-engineer:\1{ owns: ["infra/**", "deploy/**"] }', p.read_text(encoding="utf-8"))
        self.assertIn('"deploy/**"]', t.split("terraform-engineer:")[1].split("\n")[0])
        p.write_text(t, encoding="utf-8")
        (self.root / "deploy").mkdir()
        (self.root / "deploy" / "x.yaml").write_text("a: 1\n", encoding="utf-8")
        code, out = run(ORCH_LINT, self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("owned by several agents", out)

    def test_spec_reviewer_is_declared_in_plan_phase(self):
        text = (REPO / ".claude" / "orchestration.yaml").read_text(encoding="utf-8")
        plan = re.search(r"- phase: plan\n(.*?)\n\n", text, re.S).group(1)
        self.assertIn("agent: spec-reviewer", plan)
        self.assertIn("gate: human_approval", plan)


if __name__ == "__main__":
    unittest.main()


class StructureLintTest(unittest.TestCase):
    def run_in(self, n):
        root = Path(tempfile.mkdtemp(prefix="structure-"))
        self.addCleanup(shutil.rmtree, root, True)
        (root / "infra").mkdir()
        for i in range(n):
            (root / "infra" / f"f{i}.tf").write_text("x", encoding="utf-8")
        return run(REPO / "tools" / "lint" / "structure", root)

    def test_small_directory_passes(self):
        self.assertEqual(self.run_in(10)[0], 0)

    def test_large_directory_fails(self):
        code, out = self.run_in(11)
        self.assertEqual(code, 1)
        self.assertIn("infra holds 11 files", out)
