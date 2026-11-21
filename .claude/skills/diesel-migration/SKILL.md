---
name: diesel-migration
description: Write a safe Diesel migration using expand-contract.
---

# diesel-migration

- Expand-contract only: add a nullable column, write to both, backfill in batches of 10,000 rows (separate Job with progress table), read the new column, drop the old one in a later release.
- Forbidden in a release with code: `CREATE INDEX` without `CONCURRENTLY`, `ALTER COLUMN TYPE` on big tables, `NOT NULL` without a prior `CHECK ... NOT VALID`.
- `DROP`, `RENAME`, `SET NOT NULL` only in a PR labelled `contract-migration`.
- Directory names carry a time prefix; none may be older than the newest migration on main. `down.sql` is used in dev only; prod rolls forward.
