---
disable-model-invocation: true
description: Run the orchestration from .claude/orchestration.yaml for an approved spec.
argument-hint: <spec>
---

# /implement

Argument: `$ARGUMENTS` (<spec>).

1. The plan phase may run on a `draft` spec; refuse to start the build phase unless the status is `approved` (human gate).
2. Phases: plan (architect, then spec-reviewer; `high` findings block the approval gate) -> build (implement agents, one worktree per task, parallel) -> review (read-only reviewers, Opus) -> integrate (rebase worktrees, `/policy-check`, `/plan-infra dev`, `/pci-impact`, `/glossary-check`, docs-writer) -> deliver (open PR with label `ai-reviewed`).
3. Run `tools/lint/orchestration-lint` and `tools/lint/spec-lint` first; stop the phase on any failure.
4. Run every implement agent as a subagent from `.claude/agents/`; the hooks read its `agent_type`, so the ownership check applies (for `refactor-implementer` the orchestrator passes the task paths in `CLAUDE_AGENT_PATHS`). Set `CLAUDE_PHASE=deliver` only for the deliver phase. An agent that wrote a change never reviews it.
5. Before an implement agent starts a task it moves the task's GitHub issue to `In progress` and writes `specs/<spec>/progress/<task>.md` with `status: in-progress`; start it only when its `depends_on` tasks are `done`. After the review phase is green, set each reviewed task to `done` (issue status `Done`, `pr:` in the progress file).
6. Start the reviewers of the review phase automatically, in parallel and without asking, but only after every task's `acceptance` and the build `checks` have been executed and are green; if any is red or not run, stop and call no reviewer. Report the findings together.
7. Open the PR from the integration branch `<type>/<N>-<slug>`, list its tasks and issues in the description, and record the PR in each progress file; never push agent worktree branches.
