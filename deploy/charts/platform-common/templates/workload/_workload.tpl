{{- define "platform-common.workload" -}}
{{- include "platform-common.checkReplicas" . -}}
{{- if eq (.cfg.workload.kind | default "Deployment") "Rollout" -}}
{{- include "platform-common.rollout" . -}}
{{- else -}}
{{- include "platform-common.deployment" . -}}
{{- end -}}
{{- end }}
