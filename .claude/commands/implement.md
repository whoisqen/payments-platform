---
disable-model-invocation: true
description: Run the orchestration from .claude/orchestration.yaml for an approved spec.
argument-hint: <spec>
---

# /implement

Argument: `$ARGUMENTS` (<spec>).

1. Tier (`AGENTS.md`): trivial needs no spec; small and full run the build only when the spec is `approved`.
2. Phases: plan (full tier: architect, then spec-reviewer) -> build (implement agents in parallel) -> review (only when not paused, see `CLAUDE.md`) -> integrate (`/policy-check`, `/plan-infra dev`, `/pci-impact`, `/glossary-check`) -> deliver (PR from the integration branch `<type>/<N>-<slug>`).
3. Run `tools/lint/orchestration-lint` and `tools/lint/spec-lint` first; stop on any failure.
4. Per task: move its issue to In progress and write `specs/<spec>/progress/<task>.md`; start it only when its `depends_on` tasks are `done`; create `git worktree add .worktrees/<area>-<slug> -b agent/<area>-<slug>`; give the agent a prompt of at most 25 lines (task, worktree path, owned paths, manifests and one architecture section to read, checks).
5. Agents do not commit. Check their result with the commands of `AGENTS.md`, commit it to the integration branch, push, and record the PR in each progress file; after review set the task `done` and the issue Done.
