---
name: github-workflow
description: Write or change a GitHub Actions workflow safely.
---

# github-workflow

- Pin actions by SHA; minimal `permissions` per job (default `contents: read`); `id-token: write` only on jobs that assume an AWS role.
- Use `concurrency` (never cancel main or release), `timeout-minutes` on every job, reusable workflows and composite actions, and a single aggregate `ci-gate` required check.
- Pass event values through `env`, never interpolate them in `run`; run `actionlint` and `zizmor`.
- No `pull_request_target`; PRs from forks run no runners.
