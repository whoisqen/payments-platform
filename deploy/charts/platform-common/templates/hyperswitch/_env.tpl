{{/* Non-secret Hyperswitch settings as a map of environment variables; .hyperswitch.prefix is ROUTER (router, scheduler) or DRAINER */}}
{{- define "platform-common.hyperswitch.env" -}}
{{- $c := include "platform-common.hyperswitch.config" . | fromYaml -}}
{{- $hs := .hyperswitch -}}
{{- $p := $hs.prefix -}}
{{- $router := eq $p "ROUTER" -}}
{{- $g := .root.Values.global | default dict -}}
{{- $ce := .cfg.container.env | default dict -}}
{{- /* An explicit host in container.env (the generated standby layer) wins, and the derived values follow it */ -}}
{{- $db := index $ce (printf "%s__MASTER_DATABASE__HOST" $p) | default $c.database.host | default "aurora-proxy.invalid" -}}
{{- $reader := index $ce (printf "%s__REPLICA_DATABASE__HOST" $p) | default $c.database.readerHost | default $db -}}
{{- $redis := index $ce (printf "%s__REDIS__HOST" $p) | default $c.redis.host | default "memorydb.invalid" -}}
{{- /* An empty layer value replaces the default in the merge, so blanks fall back to the .invalid placeholders here */ -}}
{{- $base := $c.tenant.baseUrl | default "https://api.invalid" -}}
{{- if and $c.requireEndpoints (or (hasSuffix ".invalid" $db) (hasSuffix ".invalid" $redis) (hasSuffix ".invalid" $base)) -}}
{{- fail (printf "%s: set global.hyperswitch.database.host, redis.host and tenant.baseUrl in the cell layer" .name) -}}
{{- end -}}
{{- $rs := regexReplaceAll "^([a-z]{2})-([a-z])[a-z]*-([0-9])$" ($g.region | default "eu-central-1") "${1}${2}${3}" -}}
{{- $alias := $c.kms.keyAlias | default (printf "alias/%s-%s-%s-%s" $c.namePrefix ($g.environment | default "dev") $rs ($g.cell | default "cell-0")) -}}
{{- $l := $c.locker -}}
{{- $e := dict -}}
{{- $_ := set $e "PGSSLMODE" $c.database.sslMode -}}
{{- $_ := set $e "PGSSLROOTCERT" (ternary "/etc/ssl/rds/ca.pem" $c.database.sslRootCert (ne $c.database.caBundleConfigMap "")) -}}
{{- $_ := set $e (printf "%s__LOG__CONSOLE__ENABLED" $p) "true" -}}
{{- $_ := set $e (printf "%s__LOG__CONSOLE__LOG_FORMAT" $p) "json" -}}
{{- $_ := set $e (printf "%s__LOG__CONSOLE__LEVEL" $p) $c.logLevel -}}
{{- $dbs := list "MASTER_DATABASE" -}}
{{- if $router }}{{ $dbs = list "MASTER_DATABASE" "REPLICA_DATABASE" "ANALYTICS__SQLX" }}{{ end -}}
{{- range $dbs -}}
{{- $_ := set $e (printf "%s__%s__HOST" $p .) (ternary $db $reader (eq . "MASTER_DATABASE")) -}}
{{- $_ := set $e (printf "%s__%s__PORT" $p .) $c.database.port -}}
{{- $_ := set $e (printf "%s__%s__DBNAME" $p .) $c.database.name -}}
{{- $_ := set $e (printf "%s__%s__USERNAME" $p .) $c.database.user -}}
{{- $_ := set $e (printf "%s__%s__MAX_POOL_SIZE" $p .) (ternary $hs.poolSize ($hs.replicaPoolSize | default $hs.poolSize) (eq . "MASTER_DATABASE")) -}}
{{- end -}}
{{- if $router }}
{{- $_ := set $e "ROUTER__ANALYTICS__SOURCE" "sqlx" -}}
{{- end -}}
{{- $_ := set $e (printf "%s__REDIS__HOST" $p) $redis -}}
{{- $_ := set $e (printf "%s__REDIS__PORT" $p) $c.redis.port -}}
{{- $_ := set $e (printf "%s__REDIS__CLUSTER_ENABLED" $p) $c.redis.clusterEnabled -}}
{{- if $c.redis.clusterEnabled }}
{{- $_ := set $e (printf "%s__REDIS__CLUSTER_URLS" $p) (printf "%s:%v" $redis $c.redis.port) -}}
{{- end -}}
{{- $_ := set $e (printf "%s__REDIS__TLS_ENABLED" $p) $c.redis.tls -}}
{{- /* MemoryDB user names are unique per account and region, so each cell has its own: <cell>-<service> */ -}}
{{- $_ := set $e (printf "%s__REDIS__USERNAME" $p) (printf "%s-%s" ($g.cell | default "cell-0") $hs.redisUser) -}}
{{- /* Secrets arrive decrypted from Vault, so the secrets manager is off; KMS still encrypts data keys */ -}}
{{- $_ := set $e (printf "%s__SECRETS_MANAGEMENT__SECRETS_MANAGER" $p) "no_encryption" -}}
{{- $_ := set $e (printf "%s__ENCRYPTION_MANAGEMENT__ENCRYPTION_MANAGER" $p) "aws_kms" -}}
{{- $_ := set $e (printf "%s__ENCRYPTION_MANAGEMENT__AWS_KMS__KEY_ID" $p) $alias -}}
{{- $_ := set $e (printf "%s__ENCRYPTION_MANAGEMENT__AWS_KMS__REGION" $p) ($c.kms.region | default $g.region | default "eu-central-1") -}}
{{- $_ := set $e (printf "%s__MULTITENANCY__ENABLED" $p) "false" -}}
{{- $t := printf "%s__MULTITENANCY__TENANTS__PUBLIC" $p -}}
{{- $_ := set $e (printf "%s__BASE_URL" $t) $base -}}
{{- $_ := set $e (printf "%s__SCHEMA" $t) "public" -}}
{{- $_ := set $e (printf "%s__ACCOUNTS_SCHEMA" $t) "public" -}}
{{- $_ := set $e (printf "%s__REDIS_KEY_PREFIX" $t) "" -}}
{{- $_ := set $e (printf "%s__CLICKHOUSE_DATABASE" $t) "default" -}}
{{- $_ := set $e (printf "%s__DRAINER__STREAM_NAME" $p) $c.drainer.streamName -}}
{{- $_ := set $e (printf "%s__DRAINER__NUM_PARTITIONS" $p) $c.drainer.numPartitions -}}
{{- if $router }}
{{- $_ := set $e (printf "%s__USER__CONTROL_CENTER_URL" $t) ($c.tenant.controlCenterUrl | default "https://panel.invalid") -}}
{{- $_ := set $e "ROUTER__MULTITENANCY__GLOBAL_TENANT__TENANT_ID" "global" -}}
{{- $_ := set $e "ROUTER__MULTITENANCY__GLOBAL_TENANT__SCHEMA" "public" -}}
{{- $_ := set $e "ROUTER__MULTITENANCY__GLOBAL_TENANT__REDIS_KEY_PREFIX" "" -}}
{{- $_ := set $e "ROUTER__MULTITENANCY__GLOBAL_TENANT__CLICKHOUSE_DATABASE" "default" -}}
{{- $_ := set $e "ROUTER__LOCKER__HOST" ($l.host | default (printf "http://%s.%s.svc.cluster.local:%v" $l.service $l.namespace $l.port)) -}}
{{- $_ := set $e "ROUTER__LOCKER__MOCK_LOCKER" "false" -}}
{{- $_ := set $e "ROUTER__LOCKER__LOCKER_ENABLED" "true" -}}
{{- $_ := set $e "ROUTER__KEY_MANAGER__ENABLED" "false" -}}
{{- $_ := set $e "ROUTER__EMAIL__ACTIVE_EMAIL_CLIENT" "NO_EMAIL_CLIENT" -}}
{{- if $c.events.kafka }}
{{- $_ := set $e "ROUTER__EVENTS__SOURCE" "kafka" -}}
{{- $_ := set $e "ROUTER__EVENTS__KAFKA__BROKERS" (join "," (required "global.hyperswitch.events.brokers is required when events.kafka is true" $c.events.brokers)) -}}
{{- $topics := dict "INTENT_ANALYTICS" "payment-intent" "ATTEMPT_ANALYTICS" "payment-attempt" "REFUND_ANALYTICS" "refund" "API_LOGS" "api-log" "CONNECTOR_LOGS" "outgoing-connector" "OUTGOING_WEBHOOK_LOGS" "outgoing-webhook" "DISPUTE_ANALYTICS" "dispute" "AUDIT_EVENTS" "audit" "PAYOUT_ANALYTICS" "payout" "CONSOLIDATED_EVENTS" "consolidated" "AUTHENTICATION_ANALYTICS" "authentication" "FRAUD_CHECK_ANALYTICS" "fraud-check" "ROUTING_LOGS" "routing-api" "REVENUE_RECOVERY" "revenue-recovery" "EXTERNAL_SERVICE_CALL" "external-service-call" "ACCOUNT_UPDATER" "account-updater" -}}
{{- range $k, $v := $topics }}
{{- $_ := set $e (printf "ROUTER__EVENTS__KAFKA__%s_TOPIC" $k) (printf "%s-%s-events" $c.events.topicPrefix $v) -}}
{{- end -}}
{{- else }}
{{- $_ := set $e "ROUTER__EVENTS__SOURCE" "logs" -}}
{{- end -}}
{{- end -}}
{{- toYaml $e -}}
{{- end }}

{{/* The file of vendor/hyperswitch/config/deployments baked into the image; without -f the binary looks for config/<env>.toml, which the image does not have */}}
{{- define "platform-common.hyperswitch.configPath" -}}
{{- $c := include "platform-common.hyperswitch.config" . | fromYaml -}}
{{- printf "/app/config/deployments/%s" (.hyperswitch.configFile | default $c.configFile) -}}
{{- end }}

{{/* A secret-looking variable must come from the Vault ExternalSecret, never from a values file */}}
{{- define "platform-common.noPlainSecrets" -}}
{{- range $k, $v := .env -}}
{{- if regexMatch "(PASSWORD|SECRET|PRIVATE_KEY|ENC_KEY|HASH_KEY|API_KEY|ENCRYPTION_KEY|_DSN)$" $k -}}
{{- fail (printf "%s: %s looks like a secret; map it under secrets so it comes from Vault" $.name $k) -}}
{{- end -}}
{{- end -}}
{{- end }}
