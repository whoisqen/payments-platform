# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Working language is English: code, comments, identifiers, documentation, specs, commit messages and PR text are all written in English.

This file, `.claude/` and `specs/` are the source of truth for Claude Code configuration and for spec-driven development (SDD). They are human-owned: agents never edit `CLAUDE.md`, `.claude/**`, `.mcp.json` or `specs/_templates/**`.

## Repository state

Payment orchestrator based on Hyperswitch. Today the repository holds third-party code in `vendor/` plus Claude Code configuration, specs tooling and empty placeholders (a `README.md` each) for `docker/`, `infra/`, `deploy/`, `policy/`, `observability/`, `tests/`, `scripts/`, `docs/`. Do not invent files that the architecture describes unless asked. The full architecture ("Payments Platform: architecture and operations": SLOs, cells, DR, PCI DSS, CI/CD, ADRs) is kept in the Claude project memory as `payments-platform-architecture.md`; its section 14 defines the directory layout and naming rules.

## vendor/ is third-party code

`vendor/hyperswitch/`, `vendor/card-vault/`, `vendor/hyperswitch-e2e/` are upstream code. Do not edit them, except for an explicit patch task owned by `rust-engineer`, recorded in `vendor/UPSTREAM.md`. Sources, pinned commits and build flags are in `vendor/UPSTREAM.md`, licenses in `vendor/README.md`. Each directory is self-contained and has its own `Cargo.lock`; they cannot be merged into one workspace.

## Commands

Run from the matching `vendor/...` directory. Toolchains 1.94.1 (default) and 1.92.0 are installed through rustup (`~/.cargo` is a symlink to `/data/vlad/rust/cargo`); use `cargo +1.92.0` in `vendor/card-vault`. The commands come from the manifests and a full build has not been run.

- **vendor/hyperswitch** (Rust 1.94.1, workspace `crates/*`, binaries `router`, `scheduler`, `drainer`): `cargo build --profile release --features release --features v1`; faster build without LTO: `--profile release-fast`; one test: `cargo test -p <crate> <test_name>`. Lints are in `[workspace.lints]` (`unsafe_code = forbid`; warnings on `unwrap_used`, `expect_used`, `panic`, `indexing_slicing`, `print_stdout`). Config in `config/development.toml`; Diesel migrations in `migrations/`.
- **vendor/card-vault** (Rust 1.92.0, edition 2024, binary `locker`): `cargo +1.92.0 build --release --features release`; tests with nextest (not installed yet), profiles `default` and `ci` (`.config/nextest.toml`): `cargo nextest run --profile ci`.
- **vendor/hyperswitch-e2e** (Cypress): `npm run cypress` (interactive), `npm run cypress:ci` (headless), per-area scripts such as `cypress:payments` and `cypress:routing`, `npm run lint`, `npm run format:check`; details in its `README.md`.
- **Spec tooling:** `tools/lint/spec-lint` validates `specs/` (`--write-index` refreshes the index in `specs/README.md`); tests: `python3 -m unittest discover -s tools/lint/tests`; `tools/lint/spec-gate` is the spec gate: the `commit-msg` hook (`git config core.hooksPath tools/scripts/git-hooks`) and CI (`--range`) reject a commit whose files are not covered by a `Spec: specs/NNN-slug#Tn` task of an `approved` or `in-progress` specification; before the first specification exists `Spec: none` + `Spec-Exempt: bootstrap` is allowed, and a vendor import uses `Spec-Exempt: upstream-import`; `tools/lint/srs-lint` validates `docs/requirements/` (IDs, baseline, addenda and the re-validation of specifications that cite a changed requirement; the gate runs it for every addendum); `tools/lint/orchestration-lint` validates `.claude/orchestration.yaml` against the file tree and the agent definitions (`--strict` also fails on unowned files).

## Architecture that spans several files

- Three CDE components: **router** (public API, inbound PSP webhooks), **locker** (the only place PAN lives) and **drainer** (moves payment state from a Redis stream into PostgreSQL). Router never writes to PostgreSQL on the hot path: it stores state in key-value storage and appends to a Redis stream; drainer writes in batches (write-behind). In production the store is Amazon MemoryDB, not ElastiCache.
- The platform is split into 4 independent cells plus a spare; locker is shared by all cells.
- A PSP timeout is not a failure: the payment becomes the *unknown state* and scheduler runs *sync*. A charge is never retried automatically.
- Migrations are expand-contract only: the schema must stay compatible with the previous code version; `down.sql` is never applied in prod.
- `vendor/hyperswitch/proto/` is compiled by `crates/external_services/build.rs`.

## Spec-driven development

Every change starts with one specification in `specs/NNN-<slug>/` (`spec.md`, `plan.md`, `tasks.md`, `handoffs/`); templates are in `specs/_templates/`, the index in `specs/README.md`.

- GitHub issues are created only after the approval: `issue: none` is valid while the status is `draft` or `approved`, and a task needs its issue number before any commit may cite it.
- Ticket rules. Every task starts in the backlog as `ToDo`. The agent that takes a task moves its GitHub issue to `In progress` itself (the issue tools of `github-write` are allowed in any phase) and writes `specs/NNN-slug/progress/Tn.md` (`task`, `issue`, `status`, `agent`, `pr`; template `specs/_templates/progress.md`) before its first commit; the gate rejects a commit for a task that is not `in-progress`, and a task cannot be taken before its `depends_on` tasks are `done`. After the review phase passes, the orchestrator moves the issue to `Done` and sets `status: done` with the pull request (`#N` or URL) in the progress file; `spec-lint` rejects a `done` task without a PR. Commits carry `Refs: #<issue>`, and the PR description lists its tasks with their issues.
- `status` lifecycle: `draft` -> `approved` (human gate) -> `in-progress` -> `implemented` or `superseded`. The build phase never starts for a specification that is not `approved`; an `implemented` specification is not edited, a new change is a new specification.
- Each `tasks.md` item has `id`, `agent`, `paths`, `depends_on`, `provides`, `requires`, `acceptance`, `issue`; `paths` lie inside the agent's `owns` and do not overlap inside one parallel block. Work that spans two domains is two tasks with a `provides`/`requires` contract; an agent never edits another agent's area and writes a request to `specs/<spec>/handoffs/<from>-<to>.md` instead.
- Commands: `/spec`, `/implement`, `/review`, `/refactor`, `/policy-check`, `/plan-infra`, `/pci-impact`, `/glossary-check`, `/release`, `/incident`, `/new-service`, `/new-alert`, `/capacity`, `/new-psp`, `/hotfix` (see `.claude/commands/`). Skills are in `.claude/skills/`.
- Orchestration (`.claude/orchestration.yaml`): phases plan -> build -> review -> integrate -> deliver. One task is one worktree and one branch (`agent/<N>-<slug>-<task-id>`, local, never pushed). The PR is opened only from the integration branch `<type>/<N>-<slug>`.
- Every specification is reviewed by `spec-reviewer` (read-only, Opus) after the architect drafts `plan.md` and `tasks.md` and before the human approval gate; a `high` finding blocks approval.
- Context economy: specifications, tasks and agent instructions state only decisions an engineer cannot guess (mechanism, number, name, constraint); they never explain trivial steps, and `spec-reviewer` rates filler `medium`. SRS rows are limited to 400 characters (requirement) and 300 (implementation).
- `distributed-systems-reviewer` (read-only, Opus) checks distributed-systems principles in the review phase for `infra/`, `deploy/` and the crates; `/distributed-audit` runs it once near the end with the extra task of checking microservice patterns.
- Reviewers run automatically; nobody has to ask, but only after the acceptance checks have run and are green. For code and infrastructure the review phase of `/implement` and `/review` starts its read-only reviewers in the background only when every task's `acceptance` and the phase `checks` (pre-commit, `make test`) have been executed and passed; a red or unexecuted check stops the phase and no reviewer is called. For a specification, which has no implementation yet, the checks that must be green first are `tools/lint/spec-lint`, `orchestration-lint` and `/glossary-check`; then `spec-reviewer` starts automatically after each creation or edit of `spec.md`, `plan.md` or `tasks.md` of a non-implemented specification (after each fix round until no `high` finding is left, at most two rounds, then the human decides), and for the re-validation of a specification cited by an addendum. Findings are triaged and reported together with the result, and a reviewer never reviews its own author's change.
- Agents: the architect (`.claude/agents/plan/`) runs on Opus and writes only specs and ADR drafts; implement agents (`.claude/agents/implement/`) run on Sonnet and write only inside their `owns`; review agents (`.claude/agents/review/`) run on Opus, are read-only and see only the diff and the spec. An author never reviews their own change. The hooks read `agent_type` from the hook payload (`CLAUDE_AGENT` is a fallback), so the ownership check applies to subagents; hook scripts, `tools/lint/**` and `policy/cde-paths.yaml` are human-only.
- `touches_cde()` is true for paths listed in `policy/cde-paths.yaml`.

## Claude Code configuration

- `.claude/settings.json`: no attribution lines in commits or PRs; deny mutating `aws` calls, any `cde-*` AWS profile, edits to `deploy/envs/prod/**` and `infra/live/cde-prod/**`, reading `.env*`, `~/.aws`, `~/.kube`.
- Hooks live in `tools/scripts/claude-hooks/`: `pre_edit.py` (ownership), `pre_bash.py` (commit/PR attribution, no `git push` or `git -C` for agents), `pre_mcp.py` (one environment per session), `post_edit.py` (format, lint, tests by file type; missing tools are skipped), `stop.py` (pre-commit on changed files).
- MCP: `.mcp.json` holds only `${ENV_VAR}` references. The session works in exactly one environment, set by `CLAUDE_ENV` (default `dev`); per-environment access, roles and log sanitization levels are in `.claude/mcp/<env>.yaml`. Logs are reachable only through the sanitizing `obs-gateway`. Prod only through `/incident` with on-call approval; `cde-prod` has no MCP.
- Subagents never run `terraform apply`, touch the CDE, card data or production data, or merge; their result is always a PR. The main session may run `terraform apply`, `git push` and similar commands only on the owner's explicit request.

## Conventions

- Comments: one line only, explain why and never what; at most three lines in a row for a complex spot; no docstrings or block comments. Does not apply to `vendor/`.
- Use the terms in `docs/glossary.md` (for example *merchant*, *PSP*, *payment attempt*, *unknown state*, *sync*); `/glossary-check` flags the forbidden synonyms.
- Commits: Conventional Commits `type(scope): imperative summary` (at most 72 characters, the summary starts with a lower-case letter), scope from the list `router drainer scheduler locker control-center infra deploy policy observability docker ci claude docs vendor specs`; trailers `Refs: #N`, `Spec: specs/NNN-slug#Tn`, `PCI-Impact: none|yes` on CDE paths. One commit, one reason; each commit builds and passes tests. No AI co-authorship marks in commits or PR text.
- Branches are trunk-based and short-lived: `<type>/<N>-<slug>`; environments are directories, not branches.
- Card data (PAN, CVV) never reaches logs, traces, metrics labels or fixtures; Rust card fields use `Secret<T>`.
- Layout: every directory holds one concern and at most 10 files (`tools/lint/structure` enforces it outside `vendor/` and `.claude/`); a Terraform root holds only `main.tf`, `variables.tf`, `versions.tf` and calls modules from `modules/<concern>/`, each with its own `tests/`; configuration data goes under `config/`.
- Directory names: lower-case kebab-case; `infra/live` and `deploy/envs` share the path `<env>/<region>/<cell>`; numbering only in ADRs (`NNNN-`) and specs (`NNN-`).
