{{- define "platform-common.workload" -}}
{{- include "platform-common.checkReplicas" . -}}
{{- if eq (.cfg.workload.kind | default "Deployment") "Rollout" -}}
{{- include "platform-common.rollout" . -}}
{{- else -}}
{{- include "platform-common.deployment" . -}}
{{- end -}}
{{- include "platform-common.sentryDsn" . -}}
{{- end }}

{{/* The DSN of the service in Sentry, from AWS Secrets Manager; rendered only when container.sentryDsn.remoteKey is set */}}
{{- define "platform-common.sentryDsn" -}}
{{- $dsn := .cfg.container.sentryDsn | default dict -}}
{{- if and $dsn.envName $dsn.remoteKey }}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .name }}-sentry-dsn
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: {{ .name }}-sentry-dsn
    creationPolicy: Owner
  data:
    - secretKey: {{ $dsn.envName }}
      remoteRef:
        key: {{ $dsn.remoteKey }}
{{- end }}
{{- end }}
