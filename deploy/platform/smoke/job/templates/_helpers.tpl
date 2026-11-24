{{- define "smoke.labels" -}}
app.kubernetes.io/name: smoke
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: payments-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
payments-platform/cell: {{ required "global.cell is required" .Values.global.cell | quote }}
{{- end }}

{{- define "smoke.selector" -}}
app.kubernetes.io/name: smoke
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* The digest comes from images.yaml (smoke.image.digest); the zero digest is a placeholder */}}
{{- define "smoke.image" -}}
{{- $d := .Values.smoke.image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $d) -}}
{{- fail "smoke.image.digest must match ^sha256:[a-f0-9]{64}$" -}}
{{- end -}}
{{- if and .Values.requireResolved (eq $d (printf "sha256:%s" (repeat 64 "0"))) -}}
{{- fail "the smoke image digest is still the all-zero placeholder; CI writes it to deploy/envs/<env>/images.yaml" -}}
{{- end -}}
{{- printf "%s/%s@%s" (required "global.registry is required" .Values.global.registry) .Values.smoke.image.repository $d -}}
{{- end }}
