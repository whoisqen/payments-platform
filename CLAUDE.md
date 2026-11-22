# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Working language is English for every file, commit and PR. Rules shared with all agents, the context policy and the specification tiers are in `AGENTS.md`; read it and `manifests/project.yaml` first, other manifests only on demand. `CLAUDE.md`, `AGENTS.md`, `.claude/**`, `.mcp.json`, `manifests/**` and `specs/_templates/**` are human-owned: agents never edit them.

## Orchestrator rules (main session)

- Load on demand: never read the architecture source or a large file whole; the architecture is split by section under the memory directory (`architecture/README.md` index).
- Agent prompts at most 25 lines: task, worktree path and branch `agent/<area>-<slug>`, owned paths, which manifests and which one architecture section to read, checks to run. Create the worktree yourself: `git worktree add .worktrees/<area>-<slug> -b agent/<area>-<slug>`; do not use the Agent tool's worktree isolation (it names branches by hash).
- Agents do not commit; the orchestrator commits each package with Conventional Commits and pushes the integration branch.
- Reviewer agents are paused by the owner (cost) until the owner says otherwise; validate with local tools only.
- Keep summaries short; do not relay agent reports in full.

## vendor/

`vendor/hyperswitch/`, `vendor/card-vault/`, `vendor/hyperswitch-e2e/` are upstream code: never edit, except an explicit `rust-engineer` patch recorded in `vendor/UPSTREAM.md`. Builds: `cargo build --profile release --features release --features v1` in `vendor/hyperswitch` (Rust 1.94.1), `cargo +1.92.0 build --release --features release` in `vendor/card-vault`; not yet run.

## Spec tooling and gate

- `tools/lint/spec-lint` (`--write-index`), `tools/lint/srs-lint`, `tools/lint/orchestration-lint --strict`, `tools/lint/structure`; tests: `python3 -m unittest discover -s tools/lint/tests`.
- `tools/lint/spec-gate` runs as the `commit-msg` hook (`git config core.hooksPath tools/scripts/git-hooks`) and in CI (`--range`). A non-exempt file needs `Spec: specs/NNN-slug#Tn` of an approved or in-progress spec; exemptions: `Spec-Exempt: trivial` (tier trivial), `owner-directed` (owner told to build without a spec), `bootstrap`, `upstream-import`.
- Lifecycle `draft -> approved (human) -> in-progress -> implemented | superseded`; issues are created after approval; the orchestrator tracks tasks in `specs/<spec>/progress/Tn.md` and the GitHub project (Todo, In Progress, Done).

## Claude Code configuration

- `.claude/settings.json`: no attribution in commits or PRs; denies mutating `aws`, `cde-*` profiles and reading secrets. Local relaxations for the owner-directed session stay uncommitted.
- Hooks in `tools/scripts/claude-hooks/`: ownership (`pre_edit.py`), commands (`pre_bash.py`: infrastructure mutations, push and merge blocked for subagents), MCP environment (`pre_mcp.py`), format and lint after edits (`post_edit.py`), owns and pre-commit at stop (`stop.py`).
- MCP: `.mcp.json` holds only `${ENV_VAR}` references; one environment per session (`CLAUDE_ENV`, profiles in `.claude/mcp/<env>.yaml`).

## Conventions

- Commits: `type(scope): summary` (at most 72 characters, summary starts lower-case), scope from `router drainer scheduler locker control-center infra deploy policy observability docker ci claude docs vendor specs`; trailers `Refs: #N`, `Spec:` or `Spec-Exempt:`, `PCI-Impact: none|yes` on CDE paths (`policy/cde-paths.yaml`). No AI co-authorship marks.
- Branches and delivery: see `manifests/project.yaml` (`delivery`).
- Architecture invariants that span files are in `manifests/constraints.yaml`.
