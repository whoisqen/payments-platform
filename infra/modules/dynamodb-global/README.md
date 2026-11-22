# dynamodb-global

DynamoDB global table with the merchant-to-cell map (D2, D7).

- MREC replicas in `recovery_regions` (us-east-1, us-east-2), each with its replica KMS key; written only from Frankfurt.
- Point-in-time recovery 35 days on the table and on every replica; streams on, on-demand capacity.
- `deny_recovery_writes` is an IAM policy that denies writes in `deny_write_regions` (default: all replica regions); the switch shrinks the list.
- A resource-based deny is not used because it could block the replication service-linked role.
- No `region_role`: replicas are part of the one table, so the module behaves the same everywhere.
