# replica-bucket

Destination bucket of the state replication in one recovery region: versioned, Object Lock governance on every version,
SSE-KMS with the region's replica key, Block Public Access, TLS-only and SSE-KMS-only policy and a lifecycle rule that outlives the lock.
`writer_role_arns` (the DR apply role) may read and write `<environment>/` while the working region is down.
Local to `infra/bootstrap`; it exists once, in the recovery region us-east-1, and holds no compute.
Test: `terraform init -backend=false && terraform test`.
