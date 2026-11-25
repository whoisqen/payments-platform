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
  # Empty: the in-cluster name of the locker Service; Istio mTLS STRICT protects the hop, JWE/JWS protects the payload
  host: ""
  service: locker
  namespace: payments
  port: 3001
drainer:
  streamName: DRAINER_STREAM
  numPartitions: 64
events:
  # The upstream Kafka client sets only bootstrap.servers (no TLS, no IAM), so MSK cannot be used until it is patched
  kafka: false
  brokers: []
  topicPrefix: hyperswitch
{{- end }}

{{- define "platform-common.hyperswitch.config" -}}
{{- $g := (.root.Values.global | default dict).hyperswitch | default dict -}}
{{- toYaml (mustMergeOverwrite (include "platform-common.hyperswitch.defaults" . | fromYaml) (deepCopy $g)) -}}
{{- end }}
