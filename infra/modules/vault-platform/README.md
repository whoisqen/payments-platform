# vault-platform

AWS side of the one Vault of the platform (env `shared-services`, central cluster; it serves dev, stage and prod): regional unseal key, three Pod Identity roles and their policies. Vault itself is a chart.

- Key `alias/<prefix>-<env>-<region-short>-vault-unseal`: single-region, rotated; the awskms seal uses the alias.
- Roles `<prefix>-<env>-<region-short>-vault-{server,snapshot,bootstrap}` for service accounts `vault`, `vault-snapshot`, `vault-bootstrap` in namespace `vault`.
- Snapshots go to `raft/` of the `vault-snapshots` bucket (`s3-backup` module); the role cannot read or delete.
- Bootstrap writes only secrets named `<prefix>/<env>/vault/*`; the bucket and secrets keys are inputs.
