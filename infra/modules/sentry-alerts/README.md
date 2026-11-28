# sentry-alerts

Alerts (`sentry_alert`) of the self-hosted Sentry on the default error monitor of each project, through the `jianyuan/sentry` provider 0.17+ (token in `SENTRY_AUTH_TOKEN`).

- Two rules on every project (`projects`, or every project of `organization` at plan time): `critical` (level fatal; new, regressed or reappeared issue) and `high` (level error, priority high; new, regressed or reappeared issue). The rules of the older `sentry_issue_alert` resource are removed on the first apply.
- Both post to `slack_channel` through the Sentry Slack integration `slack_workspace_id`, at most once per `frequency_minutes` per issue.
- A project created later gets its rules on the next apply.
