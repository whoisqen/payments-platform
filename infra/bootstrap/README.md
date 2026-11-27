# bootstrap

Creates what every other stack needs, once per state root (`management`, `security`, `shared-services`, `dev`, `stage`, `prod`; the directories of `infra/live`):
the state bucket `<prefix>-<root>-euc1-tf-state-<shared-services account>` (versioning, Object Lock governance, SSE-KMS, TLS-only, Block Public Access),
its multi-Region key `alias/<prefix>-<root>-euc1-tf-state` with its us-east-1 replica and an RTC bucket replica in us-east-1, and the GitHub OIDC plan and apply roles.
Locking is the native S3 lockfile (`use_lockfile = true`) in the same bucket; no DynamoDB table exists.
The `shared-services` run goes first: it also creates the account's `workload-boundary` and GitHub OIDC provider, and no CI roles (its plan role is `live/shared-services/eu-central-1/ci-oidc-roles`).
Per root: `terraform init && terraform apply -var environment=<root>` with local state in the shared-services account (a human with a temporary admin role, never in CI),
then `backend.tf.example` -> `backend.tf`, `terraform init -migrate-state` with that root's bucket, delete the local state; put `state_kms_key_arn` into `storage.state_kms_key_arns.<root>` of `config/platform.yaml`.
A root applied before the shared-services run existed held the OIDC provider in `module.ci_roles[0]`: `terraform state rm` it there and `terraform import` it into the shared-services run.
Once `ci-oidc-roles` of prod has created `<prefix>-prod-glob-dr-apply`, set `dr_apply_role_arns` of the prod run to it. Later changes go through a PR.

## Region switch and failback

Switch: `PAY_STATE_REGION=us-east-1` makes `infra/live/terragrunt.hcl` read, write and lock in the replica
`<prefix>-<env>-use1-tf-state-<account>` with the us-east-1 replica of the state key; the DR apply role may use `<env>/` there.
The replica accepts these writes: it is versioned, Object Lock governance only keeps old versions, a lockfile delete adds
a delete marker, and its bucket and key policies grant the role. Failback, after eu-central-1 is back, with every apply frozen:
1. Apply this stack with `replication_enabled = false`, so objects that missed replication before the outage cannot
   overwrite newer state in the replica.
2. For every key under `<env>/`, check that the current replica version is the one the DR apply role wrote
   (`aws s3api head-object` shows no `ReplicationStatus: REPLICA`); otherwise copy the newest non-replica version over it.
3. Copy the state back: `aws s3 sync s3://<replica>/<env>/ s3://<state_bucket>/<env>/ --exclude '*.tflock' --sse aws:kms --sse-kms-key-id <state_kms_key_arn>`.
4. Run `terragrunt plan` of each switched unit without `PAY_STATE_REGION` and confirm the serials match the replica.
5. Apply this stack with `replication_enabled = true`; RTC copies every later write to us-east-1 again.
