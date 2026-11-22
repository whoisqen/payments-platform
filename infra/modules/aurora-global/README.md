# aurora-global

Aurora PostgreSQL 16 global database for one cell or for the locker (decisions D2, D6, D7).

- `region_role = working`: global cluster, I/O-Optimized writer in `writer_az`, readers, RDS Proxy, 35-day PITR, and headless (storage-only) secondaries in `recovery_regions`.
- `region_role = recovery`: one headless cluster joining `global_cluster_identifier`; `recovery_instance_count` adds instances and the proxy only at the switch.
- Parameter groups: `rds.force_ssl`, TLS 1.3, `pg_stat_statements`, pgaudit; `rds.global_db_rpo` is never set.
- Lag alarm above 5 s per secondary; KMS keys come from the `kms` module as inputs.
- Unverified offline: whether a headless secondary publishes `AuroraGlobalDBReplicationLag`.
