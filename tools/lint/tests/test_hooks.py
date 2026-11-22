"""Regression tests for the Claude Code hooks in tools/scripts/claude-hooks (each case was a reported bypass)."""
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
HOOKS = REPO / "tools" / "scripts" / "claude-hooks"


def hook(name, payload, **env):
    e = {k: v for k, v in os.environ.items() if k not in ("CLAUDE_AGENT", "CLAUDE_ENV", "CLAUDE_PHASE")}
    e.update(env, CLAUDE_PROJECT_DIR=str(REPO))
    p = subprocess.run([sys.executable, str(HOOKS / name)], input=json.dumps(dict(payload, cwd=str(REPO))),
                       capture_output=True, text=True, env=e)
    return p.returncode, p.stderr


def edit(agent, path, **kw):
    return hook("pre_edit.py", {"tool_name": "Edit", "tool_input": {"file_path": str(REPO / path)}, "agent_type": agent}, **kw)


def bash(cmd, agent=None):
    return hook("pre_bash.py", {"tool_name": "Bash", "tool_input": {"command": cmd}, **({"agent_type": agent} if agent else {})})


class PreEdit(unittest.TestCase):
    def test_human_session_unrestricted(self):
        self.assertEqual(edit("", "CLAUDE.md")[0], 0)

    def test_agent_inside_owns(self):
        self.assertEqual(edit("terraform-engineer", "infra/modules/x/main.tf")[0], 0)

    def test_agent_outside_owns(self):
        self.assertEqual(edit("terraform-engineer", "deploy/charts/x/Chart.yaml")[0], 2)

    def test_agents_cannot_edit_guardrails(self):
        self.assertEqual(edit("ci-engineer", "tools/scripts/claude-hooks/pre_edit.py")[0], 2)
        self.assertEqual(edit("policy-engineer", "policy/cde-paths.yaml")[0], 2)

    def test_humans_only(self):
        self.assertEqual(edit("architect", ".claude/settings.json")[0], 2)

    def test_env_fallback(self):
        code, _ = hook("pre_edit.py", {"tool_input": {"file_path": str(REPO / "CLAUDE.md")}}, CLAUDE_AGENT="docs-writer")
        self.assertEqual(code, 2)

    def test_refactor_implementer_uses_task_paths(self):
        self.assertEqual(edit("refactor-implementer", "scripts/x.py")[0], 2)
        self.assertEqual(edit("refactor-implementer", "scripts/x.py", CLAUDE_AGENT_PATHS="scripts/**")[0], 0)

    def test_malformed_payload_fails_closed_for_agent(self):
        code, _ = hook("pre_edit.py", {"tool_input": {"file_path": 5}, "agent_type": "docs-writer"})
        self.assertEqual(code, 2)


class Worktree(unittest.TestCase):
    def test_root_comes_from_the_edited_file(self):
        import shutil, tempfile
        wt = Path(tempfile.mkdtemp(prefix="wt-"))
        self.addCleanup(shutil.rmtree, wt, True)
        (wt / ".claude").mkdir()
        shutil.copy(REPO / ".claude" / "orchestration.yaml", wt / ".claude" / "orchestration.yaml")
        ok = hook("pre_edit.py", {"tool_input": {"file_path": str(wt / "infra" / "modules" / "x" / "main.tf")}, "agent_type": "terraform-engineer"})
        bad = hook("pre_edit.py", {"tool_input": {"file_path": str(wt / "deploy" / "x.yaml")}, "agent_type": "terraform-engineer"})
        self.assertEqual((ok[0], bad[0]), (0, 2))


class PreBash(unittest.TestCase):
    def test_git_global_option_does_not_hide_commit(self):
        code, _ = bash("git -c user.name=a commit -m 'x Co-Authored-By: Claude <noreply@anthropic.com>'")
        self.assertEqual(code, 2)

    def test_mention_is_not_a_commit(self):
        self.assertEqual(bash("echo 'git commit Co-Authored-By: Claude'")[0], 0)

    def test_heredoc_body_is_data(self):
        self.assertEqual(bash("cat > f <<'EOF'\nterraform apply\nEOF")[0], 0)

    def test_agent_push_and_merge(self):
        self.assertEqual(bash("git -c a=b push origin HEAD", agent="rust-engineer")[0], 2)
        self.assertEqual(bash("gh pr merge 12 --squash")[0], 2)

    def test_human_push_allowed_by_hook(self):
        self.assertEqual(bash("git push origin HEAD")[0], 0)

    def test_infra_mutations_blocked_for_agents(self):
        for cmd in ("terraform -chdir=x apply", "kubectl -n x delete pod y", "aws s3 rm s3://b/k", "helm upgrade x y",
                    "terragrunt run-all apply"):
            self.assertEqual(bash(cmd, agent="terraform-engineer")[0], 2, cmd)

    def test_main_session_may_apply(self):
        for cmd in ("terraform apply", "git push origin main"):
            self.assertEqual(bash(cmd)[0], 0, cmd)

    def test_cde_targets_blocked_for_everyone(self):
        for cmd in ("AWS_PROFILE=cde-prod aws s3 ls", "aws --profile cde-prod s3 ls"):
            self.assertEqual(bash(cmd)[0], 2, cmd)

    def test_read_only_commands_pass(self):
        for cmd in ("terraform plan", "kubectl get pods", "aws s3 ls", "helm template x"):
            self.assertEqual(bash(cmd)[0], 0, cmd)

    def test_secret_reads(self):
        self.assertEqual(bash("cat .env.local")[0], 2)
        self.assertEqual(bash("grep key ~/.aws/credentials")[0], 2)


class StopHook(unittest.TestCase):
    def test_changes_outside_owns_block_the_agent(self):
        import shutil, tempfile
        root = Path(tempfile.mkdtemp(prefix="stop-test-"))
        self.addCleanup(shutil.rmtree, root, True)
        (root / ".claude").mkdir()
        shutil.copy(REPO / ".claude" / "orchestration.yaml", root / ".claude" / "orchestration.yaml")
        run = lambda *a: subprocess.run(a, cwd=root, capture_output=True, text=True, check=True)
        run("git", "init", "-q")
        run("git", "add", ".")
        run("git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init")
        (root / "infra").mkdir()
        (root / "infra" / "a.tf").write_text("x", encoding="utf-8")
        e = dict(os.environ, CLAUDE_PROJECT_DIR=str(root))

        def stop(agent):
            p = subprocess.run([sys.executable, str(HOOKS / "stop.py")], input=json.dumps({"cwd": str(root), "agent_type": agent}),
                               capture_output=True, text=True, env=e)
            return p.returncode

        self.assertEqual(stop("terraform-engineer"), 0)
        self.assertEqual(stop("k8s-engineer"), 2)
        self.assertEqual(stop(""), 0)


class PreMcp(unittest.TestCase):
    def mcp(self, tool, **env):
        return hook("pre_mcp.py", {"tool_name": tool}, **env)[0]

    def test_read_server_allowed(self):
        self.assertEqual(self.mcp("mcp__aws-docs__search"), 0)

    def test_unknown_server_blocked_for_agents(self):
        code, _ = hook("pre_mcp.py", {"tool_name": "mcp__evil__run", "agent_type": "docs-writer"})
        self.assertEqual(code, 2)

    def test_user_plugin_allowed_for_human_session(self):
        self.assertEqual(self.mcp("mcp__plugin_claude-mem_mcp-search__work_state_write"), 0)

    def test_write_server_only_in_deliver(self):
        self.assertEqual(self.mcp("mcp__github-write__create_pull_request"), 2)
        self.assertEqual(self.mcp("mcp__github-write__create_pull_request", CLAUDE_PHASE="deliver"), 0)

    def test_merge_never(self):
        self.assertEqual(self.mcp("mcp__github-write__merge_pull_request", CLAUDE_PHASE="deliver"), 2)

    def test_prod_has_no_write_server(self):
        self.assertEqual(self.mcp("mcp__github-write__create_pull_request", CLAUDE_ENV="prod", CLAUDE_PHASE="deliver"), 2)

    def test_cde_prod_has_no_mcp(self):
        self.assertEqual(self.mcp("mcp__aws-docs__search", CLAUDE_ENV="cde-prod"), 2)


if __name__ == "__main__":
    unittest.main()
