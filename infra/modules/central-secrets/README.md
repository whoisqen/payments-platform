# central-secrets

Secrets Manager secrets of the admin tools in the central (shared-services) cluster, and the access of External Secrets Operator to them.

- Role `<prefix>-shared-services-<region-short>-central-external-secrets` with an EKS Pod Identity association on `external-secrets/external-secrets` (deploy/platform/external-secrets) in the central cluster, under the permissions boundary.
  - Allow: `secretsmanager:GetSecretValue` and `DescribeSecret` on `arn:aws:secretsmanager:<region>:<account>:secret:<prefix>/shared-services/*` only. This covers the five `*/oidc` secrets that `okta-sso` creates.
  - Allow: `kms:Decrypt` on the given key only, with `kms:ViaService = secretsmanager.<region>.amazonaws.com`.
  - Explicit deny: every Secrets Manager write action, and `kms:Encrypt`, `GenerateDataKey*`, `ReEncrypt*`, `CreateGrant`, `PutKeyPolicy`, `ScheduleKeyDeletion` on the key.
- 15 secret shells named `<prefix>/shared-services/<name>`, encrypted with `kms_key_arn`. No `aws_secretsmanager_secret_version` exists for them, so no value is in the state; the owner enters each value in Secrets Manager (console or `aws secretsmanager put-secret-value`, outside Terraform).
- Rotation is not configured: the values are entered by hand or by the owner's own procedure.
- Optional `generated_secrets = ["sentry/redis-password", ...]` (default empty): Terraform generates the first value with `random_password` (alphanumeric, 40 characters; 64 for the system key) and writes it as a secret version with `ignore_changes` on `secret_string`. The generated value is in the state, which is KMS-encrypted. Allowed: `grafana/admin` (user `admin`) and the Sentry passwords and keys. The webhook URLs, `grafana/database` and `otel-collector/tls` cannot be generated.
- Outputs: `role_arn`, `secret_arns`, `secret_names`.

## Secrets

Plain text means the whole secret string is the value (the ExternalSecret has no `property`).

| Secret | Value | Consumer |
| --- | --- | --- |
| `alertmanager/deadmans-switch-url` | plain text | deploy/platform/alertmanager |
| `alertmanager/fallback-webhook-url` | plain text | deploy/platform/alertmanager |
| `alertmanager/slack-payments-alerts` | plain text | deploy/platform/alertmanager |
| `alertmanager/slack-payments-critical` | plain text | deploy/platform/alertmanager |
| `alertmanager/slack-security` | plain text | deploy/platform/alertmanager |
| `grafana/admin` | JSON `user`, `password` | deploy/platform/grafana (externalsecret-admin) |
| `grafana/database` | JSON `host`, `name`, `user`, `password` | deploy/platform/grafana (externalsecret-database) |
| `otel-collector/tls` | JSON `ca.crt`, `tls.crt`, `tls.key` (PEM) | deploy/platform/otel-collector |
| `sentry/admin-password` | plain text | deploy/platform/sentry (sentry-secrets) |
| `sentry/clickhouse-password` | plain text | deploy/platform/sentry |
| `sentry/launchpad-rpc-secret` | plain text | deploy/platform/sentry |
| `sentry/postgres-password` | plain text | deploy/platform/sentry |
| `sentry/postgres-replication-password` | plain text | deploy/platform/sentry |
| `sentry/redis-password` | plain text | deploy/platform/sentry |
| `sentry/system-secret-key` | plain text | deploy/platform/sentry |

Created by `okta-sso`, not here: `grafana/oidc`, `argocd/oidc`, `vault/oidc`, `proxy/oidc`, `sentry/oidc` (JSON `client_id`, `client_secret`, `auth_url`, `token_url`, `api_url`, `issuer`).

Check against deploy after a change: `git grep -h -o -E "key: pay/shared-services/[A-Za-z0-9/_-]+" -- deploy`.
