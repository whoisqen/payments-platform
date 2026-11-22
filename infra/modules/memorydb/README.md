# memorydb

MemoryDB (Redis OSS API) for one cell: 2 shards x (1 primary + 2 replicas) over three AZs, TLS, ACL with IAM-authenticated users.

- Native snapshots daily with 35-day retention; the hourly 35-day snapshots and their copies to us-east-1 and us-east-2 are made by the `backup` module through the `backup-tier` tag (D3, D7).
- Not replicated across regions (D7): no multi-Region cluster; recovery rebuilds from Aurora.
- `maxmemory-policy noeviction` protects the payment streams.
- KMS key, subnets and security groups are inputs; no `region_role` because the module runs only where compute may run.
