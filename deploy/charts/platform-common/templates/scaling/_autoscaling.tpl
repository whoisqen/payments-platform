{{- define "platform-common.autoscaling" -}}
{{- $a := .cfg.autoscaling | default dict -}}
{{- if $a.enabled -}}
{{- if eq $a.kind "keda" -}}
{{- include "platform-common.scaledobject" . -}}
{{- else -}}
{{- include "platform-common.hpa" . -}}
{{- end -}}
{{- end -}}
{{- end }}
