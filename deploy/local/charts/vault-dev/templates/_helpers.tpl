{{- define "vault-dev.labels" -}}
app.kubernetes.io/name: vault
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: payments-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "vault-dev.selector" -}}
app.kubernetes.io/name: vault
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "vault-dev.securityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end }}
