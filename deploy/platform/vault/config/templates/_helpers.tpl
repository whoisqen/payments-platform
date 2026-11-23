{{- define "vault-config.labels" -}}
app.kubernetes.io/name: vault-config
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: payments-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Fails a render that still carries a REPLACE_* placeholder once the environment layer sets requireResolved */}}
{{- define "vault-config.guard" -}}
{{- if .Values.requireResolved -}}
{{- if contains "REPLACE_" (toYaml .Values) -}}
{{- fail "unresolved REPLACE_* placeholder in values" -}}
{{- end -}}
{{- if eq (include "vault-config.digest" .) (repeat 64 "0" | printf "sha256:%s") -}}
{{- fail "the snapshot image digest is still the all-zero placeholder; CI writes it to deploy/envs/<env>/images.yaml" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Digest from images.yaml (key vault-snapshot) when present, else snapshot.image.digest */}}
{{- define "vault-config.digest" -}}
{{- $img := (index .Values "vault-snapshot" | default dict).image | default dict -}}
{{- $img.digest | default .Values.snapshot.image.digest -}}
{{- end }}

{{- define "vault-config.image" -}}
{{- printf "%s@%s" .Values.snapshot.image.repository (include "vault-config.digest" .) -}}
{{- end }}
