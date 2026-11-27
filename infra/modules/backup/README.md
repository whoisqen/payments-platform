# backup

AWS Backup vaults, plans and restore tests (D2, D3, D5, D7); stateful resources join a plan by their `backup-tier` tag.

- Vaults in the provider region and in `recovery_regions`, encrypted with backup-account keys, Vault Lock in compliance mode (min 7, max 2555 days), policy that admits only `CopyIntoBackupVault` from `source_account_ids`.
- gold: hourly 35 days with copies to us-east-1, continuous 35 days, monthly 7 years; silver: hourly 35 days with copies; bronze: daily 7 days.
- Daily restore test of Aurora and DynamoDB tagged gold; no cold storage rule, so managed snapshots keep their native tier.
- `create_plans = false` gives a backup-account stack with only vaults; a workload stack passes their ARNs in `copy_vault_arns`.
- `region_role = recovery` creates one locked vault and nothing else.
