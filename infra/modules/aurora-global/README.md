# aurora-global

Aurora PostgreSQL 16 global database for one cell or for the locker.

- `region_role = working`: global cluster, I/O-Optimized writer in `writer_az`, readers, RDS Proxy, 35-day PITR, and headless (storage-only) secondaries in `recovery_regions`.
- `region_role = recovery`: one cluster joining `global_cluster_identifier`; `recovery_instance_count` adds warm-standby readers (`recovery_instance_class`, default reader class); the RDS Proxy appears only with `proxy_secret_arn`.
- Parameter groups: `rds.force_ssl`, TLS 1.3, `pg_stat_statements`, pgaudit; `rds.global_db_rpo` is never set.
- Lag alarm above 5 s per secondary; KMS keys come from the `kms` module as inputs.
- Unverified offline: whether a headless secondary publishes `AuroraGlobalDBReplicationLag`.
- `proxy_auth_entries`: extra password logins (iam_auth DISABLED or REQUIRED, SCRAM) with a module-made empty KMS secret or a passed-in one; the `locker_app` value is set out of band, mirrored in Vault `secret/<env>/locker/database` and rotated together.
