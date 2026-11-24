# AI review of pull requests

Advisory review of each pull request: `review.py` builds a redacted diff, calls a Bedrock model and keeps one comment up to date.
It never approves, blocks or becomes a required check. Settings: `config/ai-review.yaml`. Workflow: `.github/workflows/ai-review.yml`.

## Trust model

- The code that runs (`tools/ai`, `config`, `policy`) comes from the base commit of the pull request. The head is fetched as git objects
  (`refs/pull/N/head`) and only read through `git diff` and `git show`; it is never checked out, imported or executed.
- The workflow has two jobs. `plan` has no cloud access and decides whether to review. `review` runs in the GitHub environment
  `ai-review` and is the only job with `id-token: write`.
- Known limit: the workflow file itself comes from the pull request (`pull_request` event), so a same-repository author can edit it.
  Closing this needs the `pull_request_target` trigger with the same base-checkout pattern; that is an owner decision.
- Fork pull requests are skipped before any credential is requested.

## AWS side (Terraform)

The job's OIDC subject is `repo:<org>/<repo>:environment:ai-review`. The role in `AI_REVIEW_ROLE_ARN` (repository variable) must:

- trust `token.actions.githubusercontent.com` with `aud = sts.amazonaws.com` and `sub` equal (`StringEquals`, no wildcard) to
  `repo:<org>/<repo>:environment:ai-review`;
- allow `bedrock:InvokeModel` on the inference profile and the foundation models behind it, and `bedrock:ApplyGuardrail` on the
  guardrail ARN when `model.guardrail.id` is set (to be confirmed against the Bedrock documentation when the guardrail is created).

Create the GitHub environment `ai-review` without required reviewers (they would block every run).

## When a review runs

`trigger` in `config/ai-review.yaml`: always on `opened` and `ready_for_review`; on the label `ai-review:run`; on a push only when the
head sha changed and the last review comment is at least `min_minutes_between_reviews` old. The comment carries the reviewed head sha
in a hidden line. Draft pull requests, the label `ai-review:skip`, bot authors and documentation-only changes are skipped.

## Redaction

`sanitize.py` runs on the raw diff lines before line numbers are added and before any size cut. It normalises the text (NFKC,
zero-width characters, non-ASCII digits), undoes JSON escapes and replaces card numbers, keys, tokens, secret assignments (including
quoted spans and YAML block scalars), Kubernetes Secret data and base64 values that decode to a secret. Line breaks are preserved, so
finding line numbers stay valid. Nothing the model receives or returns is printed or written to a file; only exception types are logged.

## Dependencies

`requirements.in` lists the direct pins. `install-deps.sh` installs `requirements.txt` with `--require-hashes --no-deps`; without that
file the review is switched off with a warning. The lock file needs network access to the package index, so the owner generates it:

```
cd tools/ai
uv pip compile requirements.in --generate-hashes --python-version 3.12 --no-header -o requirements.txt
```

Use the Python version of the runner (`ubuntu-latest`). Review the diff of `requirements.txt` and commit it.

## Tests

`python3 -m unittest discover -s tools/ai`. Test fixtures build every secret and card number at run time.
