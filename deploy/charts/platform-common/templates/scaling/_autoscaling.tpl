{{- define "platform-common.autoscaling" -}}
{{- $a := .cfg.autoscaling | default dict -}}
{{- if include "platform-common.workingHours" . -}}
{{- include "platform-common.scaledobject" . -}}
{{- else if $a.enabled -}}
{{- if eq $a.kind "keda" -}}
{{- include "platform-common.scaledobject" . -}}
{{- else -}}
{{- include "platform-common.hpa" . -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* Non-empty when global.workingHours is set: the workload runs inside the window and scales to zero outside it */}}
{{- define "platform-common.workingHours" -}}
{{- with ((.root.Values.global | default dict).workingHours) }}{{ if .start }}true{{ end }}{{ end -}}
{{- end }}

{{/* The replica count is owned by an HPA or a ScaledObject, so the workload must not set it */}}
{{- define "platform-common.scaled" -}}
{{- if or (.cfg.autoscaling | default dict).enabled (include "platform-common.workingHours" .) }}true{{ end -}}
{{- end }}
