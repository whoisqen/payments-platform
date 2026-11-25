# memorydb

MemoryDB (Redis OSS API) for one cell: 2 shards x (1 primary + 2 replicas) over three AZs, TLS, ACL with IAM- and password-authenticated users.

- Native snapshots daily with 35-day retention; the hourly 35-day snapshots and their copies to us-east-1 and us-east-2 are made by the `backup` module through the `backup-tier` tag (D3, D7).
- Not replicated across regions (D7): no multi-Region cluster; recovery rebuilds from Aurora.
- `maxmemory-policy noeviction` protects the payment streams.
- KMS key, subnets and security groups are inputs; no `region_role` because the module runs only where compute may run.

## Users

- `users`: IAM authentication, no password. `password_users`: password authentication for clients that cannot sign IAM tokens (Hyperswitch router, drainer, scheduler). A key may sit in only one map.
- User names are unique per account and region, so every name is `user_name_prefix` + key; the live units pass `<cell>-` (`cell-0-router`, `spare-drainer`). Output `user_names` maps each key to its name; the Helm value `redisUser` of each service must match it.
- No password is kept in state: MemoryDB has no write-only password argument, so Terraform creates each password user with a throwaway 64-character `random_password` (in state only, never in Vault) and ignores `authentication_mode[0].passwords` afterwards. The real password is applied out of band; the first rotation below is mandatory before the service is deployed.
- Switching an existing user between IAM and password needs `terraform apply -replace` of that user, because the password is ignored.

## Password rotation (with Vault)

MemoryDB accepts two passwords per user, so rotation has no downtime. Per cell and service (`router`, `drainer`, `scheduler`):

1. Generate a password of 32 to 128 printable characters without spaces.
2. Add it next to the current one: `aws memorydb update-user --user-name <cell>-<service> --cli-input-json file://<tmpfs file>` with `AuthenticationMode: {Type: password, Passwords: [<old>, <new>]}`; for the first rotation the old one is omitted. Keep passwords off the command line and shell history.
3. Write the new value to Vault `secret/<env>/<cell>/<service>/redis` (field `password`); wait for the ExternalSecret refresh and restart the deployment.
4. Once every pod runs with the new value, run `update-user` again with only the new password.
