# secrets-replica

Secrets Manager secrets with a multi-Region replica in us-east-1, encrypted with the replica KMS key of that region (D7).

- Creates containers only; no `aws_secretsmanager_secret_version`, so no value ever enters state or code.
- Names follow `pay-<env>-<region-short>-<key>`.
- A replica is read-only until it is promoted at the switch.
- No `region_role`: the replicas are an attribute of each secret, so one behaviour fits every region.
