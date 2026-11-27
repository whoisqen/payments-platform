{{/* Cell-wide Hyperswitch settings; global.hyperswitch in the payments-cell layers overrides any of them */}}
{{- define "platform-common.hyperswitch.defaults" -}}
namePrefix: pay
# The payments-cell umbrella sets it, so a cell layer without real endpoints fails the render
requireEndpoints: false
configFile: production.toml
logLevel: INFO
database:
  host: aurora-proxy.invalid
  readerHost: ""
  port: 5432
  name: hyperswitch
  user: hs_app
  sslMode: verify-full
  # RDS Proxy presents an ACM certificate that chains to the Amazon Trust Services roots of the system bundle
  sslRootCert: /etc/ssl/certs/ca-certificates.crt
  # ConfigMap with the RDS CA bundle (key ca.pem); needed only for a direct Aurora endpoint, it then replaces sslRootCert
  caBundleConfigMap: ""
redis:
  host: memorydb.invalid
  port: 6379
  clusterEnabled: true
  tls: true
kms:
  # Empty: alias/<namePrefix>-<env>-<region short>-<cell>, the cell key of the kms-set stack
  keyAlias: ""
  region: ""
tenant:
  baseUrl: https://api.invalid
  controlCenterUrl: https://panel.invalid
locker:
  # Full URL override; empty: built from clusterDomain, or the in-cluster Service when clusterDomain is empty too
  host: ""
  # The locker runs in its own cluster per environment and region: <service>.<namespace>.svc.locker.<clusterDomain>, as the edge names the cells
  clusterDomain: ""
  service: locker
  namespace: payments
  port: 3001
drainer:
  streamName: DRAINER_STREAM
  numPartitions: 64
events:
  # On where the region has MSK; the patched producer (vendor/UPSTREAM.md) speaks TLS with IAM auth on port 9098
  kafka: false
  brokers: []
  # <topicPrefix>-<event>-events, the names the ClickHouse Kafka tables of upstream consume
  topicPrefix: hyperswitch
  securityProtocol: SASL_SSL
  saslMechanism: OAUTHBEARER
  oauthbearerProvider: aws_msk_iam
  # Empty: global.region
  awsRegion: ""
{{- end }}

{{- define "platform-common.hyperswitch.config" -}}
{{- $g := (.root.Values.global | default dict).hyperswitch | default dict -}}
{{- toYaml (mustMergeOverwrite (include "platform-common.hyperswitch.defaults" . | fromYaml) (deepCopy $g)) -}}
{{- end }}
