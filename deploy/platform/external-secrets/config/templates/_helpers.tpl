{{- define "external-secrets-config.labels" -}}
app.kubernetes.io/name: external-secrets-config
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: payments-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Fails a render that still carries a REPLACE_* placeholder once the environment layer sets requireResolved */}}
{{- define "external-secrets-config.guard" -}}
{{- if .Values.requireResolved -}}
{{- if contains "REPLACE_" (toYaml .Values) -}}
{{- fail "unresolved REPLACE_* placeholder in values" -}}
{{- end -}}
{{- end -}}
{{- end }}
