# bootstrap

Creates what every other stack needs: the state bucket (versioning, Object Lock governance, SSE-KMS with a
multi-Region key, TLS-only, Block Public Access), replicas with RTC in us-east-1 and us-east-2, and the GitHub OIDC
plan and apply roles. Locking is the native S3 lockfile (`use_lockfile = true`); no DynamoDB table is created.
Order: 1) create the permissions boundary and run `terraform init && terraform apply` here with local state
(shared-services account, a human with a temporary admin role, never in CI); 2) copy `backend.tf.example` to
`backend.tf` and `terraform init -migrate-state` with the bucket and key from the outputs; 3) delete the local state file;
4) live components use the bucket with prefix `<env>/<component>/` and the apply roles. Later changes go through a PR.
