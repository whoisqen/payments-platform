# opensearch-indices

Index layer of the central log domain through the `opensearch` provider (SigV4, signed as the master role; the domain is VPC-only, so it runs from the in-VPC CI runners).

- Data streams `logs-app-<env>` and `logs-audit` from composable templates (3 primaries, 1 replica), created up front; `@timestamp` date, `resource.k8s.namespace.name`, `resource.service.name`, `severity.text` keyword, `body` text, `attributes` flat_object.
- ISM `logs-app`: rollover at 30 GB per primary shard or 1 day, hot 7 days, UltraWarm until day 30, delete. `logs-audit`: 10 GB or 1 day, hot 30 days, UltraWarm until day 365, delete. Shard sizes are validated to 10-50 GB.
- Read roles `logs_sre`, `logs_security` (app and audit), `logs_engineering` (app only) for the SAML groups, `kibana_user` for every group; `logs_reader_<env>` for the admin agent role of each environment (`logs-app-<env>` only).
- Writer roles `logs_app_writer` (Logstash IRSA role) and `logs_audit_writer` (ingestion pipeline role).
- `logs_grafana` (`logs-app-*`) for `grafana_role_arns`; `logs_monitor` (`cluster:monitor/*`, `indices:monitor/*` on every index) for `monitor_role_arns` (elasticsearch_exporter).
- Owns the `all_access` and `security_manager` mappings: the master role and the admin group.
