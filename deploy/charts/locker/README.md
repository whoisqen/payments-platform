# locker

Card vault chart on the `platform-common` library, canary-rolled by Istio weight.
`securityGroupPolicy.securityGroupIds` is required: the Terraform `locker_pod` security group
(`locker_pod_security_group_id`), the only one allowed to reach the card-vault Aurora proxy.
The value is `REPLACE_LOCKER_POD_SG_ID` until the env values set it.
The SecurityGroupPolicy needs `ENABLE_POD_ENI` on the VPC CNI.

## Runtime configuration

- `config` holds the non-secret card-vault sections and renders them as `LOCKER__<SECTION>__<KEY>` env (the image has no `production.toml`); `tenants` adds `tenant_secrets.<id>.schema` and `redis_key_prefix`. The schema rejects secret keys in `config` and any `LOCKER__` key in `container.env`.
- TLS: no `tls` section. Istio (PeerAuthentication STRICT, workload certificates from istio-csr) terminates mTLS from the router in the sidecar, and the AuthorizationPolicy admits only the router identity; a cert-manager certificate in the app would put a second TLS layer under the mesh and break the HTTP routing of the canary.
- Database: RDS Proxy endpoint, libpq `PGSSLMODE=verify-full` against the system CA bundle. The password is static in Vault KV: card-vault reads it once at start into a fixed pool, and the proxy authenticates users only through its Secrets Manager secrets, so Vault dynamic credentials cannot work.
- `secrets_management` is `aws_kms` with the locker key alias `alias/pay-<env>-<region-short>-locker`; every secret value below is KMS ciphertext (base64), decrypted at start under the locker Pod Identity role. `external_key_manager` stays `disabled` (it is an HTTP key-manager service, not KMS). No Redis: KV mode stays off.
- NetworkPolicy: besides the `platform-common` rules, TCP 443 to `global.endpointCidrs` (KMS and STS interface endpoints), TCP 80 to the Pod Identity agent `169.254.170.23/32` (IPv4 only, the clusters are not dual-stack) and TCP 9091 from the `monitoring` namespace.
- Metrics: card-vault serves `/metrics` on its own listener, the container port `metrics` (9091); the Service and the ServiceMonitor use that port.
- Secrets: ExternalSecret `locker-secrets` from ClusterSecretStore `vault` (mount `secret`, KV v2); a rotation needs a rollout restart.

| Vault key (`secret/<env>/locker/...`) | Properties | Env |
|---|---|---|
| `database` | `password` | `LOCKER__DATABASE__PASSWORD` |
| `jwe` | `locker-private-key` (the router holds its public half) | `LOCKER__SECRETS__LOCKER_PRIVATE_KEY` |
| `tenants/<id>` | `master-key` (hex AES key), `public-key` (router JWS/JWE public key) | `LOCKER__TENANT_SECRETS__<ID>__*` |
| `external-key-manager` | `ca-cert`, `client-identity` (only `enabled_with_mtls`) | `LOCKER__EXTERNAL_KEY_MANAGER__CA_CERT`, `LOCKER__API_CLIENT__IDENTITY` |

Vault (owned by `deploy/platform/vault`): policy `locker-<env>-read` with `path "secret/data/<env>/locker/*" { capabilities = ["read"] }`, attached to the Kubernetes auth role `external-secrets` (service account `external-secrets/external-secrets`) of the cluster that runs the locker; no role for the locker pod itself.
