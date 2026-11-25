{{/* .secrets maps a variable to {key, property}; key is relative to <env>/<cell>/ of the KV v2 mount behind the ClusterSecretStore vault */}}
{{- define "platform-common.vaultSecret" -}}
{{- if .secrets }}
{{- $g := .root.Values.global | default dict }}
{{- $env := required "global.environment is required to build the Vault path" $g.environment }}
{{- $cell := required "global.cell is required to build the Vault path" $g.cell }}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .name }}-vault
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  # Pods read the values at start only; a rotated value reaches them with the next rollout
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault
  target:
    name: {{ .name }}-vault
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    {{- range $var, $ref := .secrets }}
    {{- if not (regexMatch "^[a-z0-9-]+(/[a-z0-9_-]+)+$" $ref.key) }}
    {{- fail (printf "secrets.%s.key %q must be a relative path such as router/database" $var $ref.key) }}
    {{- end }}
    - secretKey: {{ $var }}
      remoteRef:
        key: {{ printf "%s/%s/%s" $env $cell $ref.key }}
        property: {{ required (printf "secrets.%s.property is required" $var) $ref.property }}
    {{- end }}
{{- end }}
{{- end }}
