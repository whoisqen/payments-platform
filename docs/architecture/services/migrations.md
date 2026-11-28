# migrations

The schema change Job that runs before every rollout of a cell or of the locker. Chart `deploy/charts/migrations`, installed by the `payments-cell` umbrella (as `migrations`) and the `payments-locker` umbrella (as `locker-migrations`). Owner team: `payments-core`. CDE: yes.

## What it does and why it exists

A new router or locker version may need a new column or table. The Job applies that change before the new pods start, and only after a backup exists:

1. **Snapshot** (init container `pre-migration-snapshot`, `/opt/migrator/snapshot.sh`): starts an AWS Backup job of the database, labelled `<release>-rev<revision>`, kept 35 days, and waits up to 1,200 s until the recovery point is available. `scripts/schema/pre-migration-snapshot.sh` does the same for operators: an AWS Backup job with a 35-day lifecycle, tagged `change=<label>`.
2. **Migrate** (container `migrate`, `/opt/migrator/migrate.sh`): applies the migrations in `expand-only` mode, with `lock_timeout` 5 s and `statement_timeout` 10 minutes. It takes an advisory lock, so two Jobs never run DDL at once.
3. **Backfill** (optional, `backfill.enabled: false` by default): a separate Job that fills new columns in batches of 10,000 while replica lag stays under 500 ms. It runs outside the hook, so a deployment never waits for it.

Expand-only means a migration may add, never remove. A destructive (contract) change ships in its own pull request with the `contract-migration` label, after no running version uses the old schema. `.squawk.toml` configures the SQL linter that checks migrations in CI.

## Requests it takes and calls it makes

| Direction | Peer | Port and protocol | Purpose |
|---|---|---|---|
| in | none | n/a | the NetworkPolicy admits no ingress |
| out | Aurora writer endpoint (not RDS Proxy) | 5432 TLS `verify-full`, user `hs_migrator` | DDL; the advisory lock needs one stable connection |
| out | AWS APIs through VPC interface endpoints (`global.endpointCidrs`) | 443 | AWS Backup start and wait |
| out | DNS | 53 | name resolution |

## Data it reads and writes

| Store | Reads | Writes |
|---|---|---|
| [Cell Aurora](data-stores.md#cell-aurora), database `hyperswitch` | migration history | schema changes |
| [Locker Aurora](data-stores.md#locker-aurora), database `locker` (`locker-migrations`) | migration history | schema changes |
| AWS Backup vault | recovery point status | an on-demand recovery point per migration |

Migrations come from `vendor/hyperswitch/migrations` and `vendor/card-vault/migrations`.

## Configuration and secrets

| Setting | Cell | Locker |
|---|---|---|
| `database.host` | writer endpoint, set in `deploy/envs/<env>/<region>/<cell>/values.yaml` (`migrations.database.host`) | `deploy/envs/<env>/<region>/locker/values.yaml` (`locker-migrations.database.host`) |
| `database.name` | `hyperswitch` | `locker` |
| `database.user` | `hs_migrator` | `hs_migrator` (chart default) |
| Image | `migrator` by digest; it moves with the router digest | same |

`hs_migrator` is the only role with DDL rights and signs in through EKS Pod Identity (IAM database authentication), so the Job needs no password and has no Vault path. The service account is `migrator`; its token is not mounted into the pod (`automountServiceAccountToken: false`).

## Scaling and resources

- One pod per run. `backoffLimit: 0`: DDL is never repeated automatically; a retry is a new sync or a fix through a pull request.
- `activeDeadlineSeconds: 2100` (900 s of migration plus the snapshot wait); finished Jobs are kept for 24 hours.
- 250m CPU and 256 MiB, memory limit 256 MiB.
- Helm hook `pre-install,pre-upgrade`, weight -10; its NetworkPolicy is a hook too, created first. No Istio sidecar, so the Job can complete.

## Failure modes and what the user sees

| Failure | Effect | User sees |
|---|---|---|
| Snapshot not available within 1,200 s | the init container fails; the Job fails; the rollout stops | nothing; the old version keeps running |
| Lock not acquired within 5 s | the migration fails instead of queueing behind live traffic | nothing; the old version keeps running |
| Statement longer than 10 minutes | the migration fails | nothing; the old version keeps running |
| A migration breaks data | restore from the pre-migration snapshot or point-in-time recovery | depends on the change; the [backups page](../foundation/data-backups.md) has the targets |

## Metrics and alerts

| Alert | Condition | Severity | Runbook |
|---|---|---|---|
| `MigrationJobFailed` | `kube_job_status_failed` above 0 for a Job named like `*migrat*` | warning | [migration-job-failed](../../runbooks/application/warnings.md#migration-job-failed) |
| `BackupJobFailed` | an AWS Backup job failed | critical | [backup-job-failed](../../runbooks/backup-dr/backup-job-failed.md) |

## Where in the repo

| Path | What |
|---|---|
| `deploy/charts/migrations/` | Job, backfill Job, NetworkPolicy, service account |
| `scripts/schema/pre-migration-snapshot.sh` | Snapshot script and its tests |
| `.squawk.toml` | Migration linter settings |
| `vendor/hyperswitch/migrations`, `vendor/card-vault/migrations` | The migrations themselves |
