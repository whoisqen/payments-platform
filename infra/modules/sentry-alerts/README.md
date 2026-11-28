# sentry-alerts

Issue alert rules of the self-hosted Sentry, through the `jianyuan/sentry` provider (token in `SENTRY_AUTH_TOKEN`).

- Two rules on every project (`projects`, or every project of `organization` at plan time): `critical` (level fatal; new, regressed or reappeared issue) and `high` (level error; new or existing high-priority issue).
- Both post to `slack_channel` through the Sentry Slack integration `slack_workspace_id`, at most once per `frequency_minutes` per issue.
- A project created later gets its rules on the next apply.
