# replica-bucket

Destination bucket of the state replication in one recovery region: versioned, Object Lock governance on every version,
SSE-KMS with the region's replica key, Block Public Access, TLS-only policy and a lifecycle rule that outlives the lock.
Local to `infra/bootstrap`; it exists once per recovery region and holds no compute.
Test: `terraform init -backend=false && terraform test`.
