# bootstrap

Creates what every other stack needs: the state bucket (versioning, Object Lock governance, SSE-KMS with a
multi-Region key, TLS-only, Block Public Access), its replica with RTC in us-east-1, and the GitHub OIDC
plan and apply roles. Locking is the native S3 lockfile (`use_lockfile = true`); no DynamoDB table is created.
Order: 1) create the permissions boundary and run `terraform init && terraform apply` here with local state
(shared-services account, a human with a temporary admin role, never in CI); 2) copy `backend.tf.example` to
`backend.tf` and `terraform init -migrate-state` with the bucket and key from the outputs; 3) delete the local state file;
4) live components use the bucket with prefix `<env>/<component>/` and the apply roles; 5) once `ci-oidc-roles` of the
environment has created `<prefix>-<env>-glob-dr-apply`, set `dr_apply_role_arns` to it. Later changes go through a PR.

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
