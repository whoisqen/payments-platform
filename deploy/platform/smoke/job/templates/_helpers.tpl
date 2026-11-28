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

{{/* CI writes the digest to deploy/envs/<env>/images.yaml as images.smoke; smoke.image.digest is the fallback of the chart defaults */}}
{{- define "smoke.digest" -}}
{{- $img := .Values.images | default dict -}}
{{- $img.smoke | default .Values.smoke.image.digest | default "" -}}
{{- end }}

{{/* Renders "true" only for a real digest: a missing, malformed or all-zero value yields no objects at all, so the cell syncs as before and no PostSync hook exists */}}
{{- define "smoke.enabled" -}}
{{- $d := include "smoke.digest" . -}}
{{- if and (regexMatch "^sha256:[a-f0-9]{64}$" $d) (ne $d (printf "sha256:%s" (repeat 64 "0"))) -}}true{{- else if include "smoke.tag" . -}}true{{- end -}}
{{- end }}

{{/* A tag only on a local cluster (global.localCluster), whose images are loaded without a registry digest */}}
{{- define "smoke.tag" -}}
{{- if .Values.global.localCluster }}{{ .Values.smoke.image.tag | default "" }}{{ end -}}
{{- end }}

{{- define "smoke.image" -}}
{{- $d := include "smoke.digest" . -}}
{{- $r := required "global.registry is required" .Values.global.registry -}}
{{- if and (regexMatch "^sha256:[a-f0-9]{64}$" $d) (ne $d (printf "sha256:%s" (repeat 64 "0"))) -}}
{{- printf "%s/%s@%s" $r .Values.smoke.image.repository $d -}}
{{- else -}}
{{- printf "%s/%s:%s" $r .Values.smoke.image.repository (include "smoke.tag" .) -}}
{{- end -}}
{{- end }}
