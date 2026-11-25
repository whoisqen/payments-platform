# aurora-global

Aurora PostgreSQL 16 global database for one cell or for the locker.

- `region_role = working`: global cluster, I/O-Optimized writer in `writer_az`, readers, RDS Proxy, 35-day PITR, and headless (storage-only) secondaries in `recovery_regions`.
- `region_role = recovery`: one cluster joining `global_cluster_identifier`; `recovery_instance_count` adds warm-standby readers (`recovery_instance_class`, default reader class); the RDS Proxy appears only with `proxy_secret_arn`.
- Parameter groups: `rds.force_ssl`, TLS 1.3, `pg_stat_statements`, pgaudit; `rds.global_db_rpo` is never set.
- Lag alarm above 5 s per secondary; KMS keys come from the `kms` module as inputs.
- Unverified offline: whether a headless secondary publishes `AuroraGlobalDBReplicationLag`.
- `proxy_auth_entries`: extra password logins (iam_auth DISABLED or REQUIRED, SCRAM) with a module-made empty KMS secret or a passed-in one; the `locker_app` value is set out of band, mirrored in Vault `secret/<env>/locker/database` and rotated together.
- Cells pass `proxy_auth_entries = [hs_app]` from `_envcommon/data/aurora.hcl` (locker units replace the list with `locker_app`): router, drainer and scheduler share the login `hs_app`, matching the Helm value `database.user`. The PostgreSQL role `hs_app` (LOGIN, SCRAM password, grants on the `hyperswitch` schema) is created by the database bootstrap, not by Terraform.

## hs_app password rotation (with Vault)

PostgreSQL keeps one password per role, so new connections with the old value fail between steps 2 and 4; existing proxy connections stay open. Run it in a quiet window per cell:

1. Generate a password of at least 32 characters.
2. As the master user, `\password hs_app` in psql: it sends only the SCRAM verifier, so the plain value never reaches pgaudit or the logs.
3. `aws secretsmanager put-secret-value` on `<cluster name>/proxy/hs_app` with `{"username":"hs_app","password":"<new>"}` from a tmpfs file; after a switch, also the secret of the recovery-region proxy.
4. Write the same value to Vault `secret/<env>/<cell>/{router,drainer,scheduler}/database` (field `password`; all three paths hold one value) and restart the three deployments after the ExternalSecret refresh.
