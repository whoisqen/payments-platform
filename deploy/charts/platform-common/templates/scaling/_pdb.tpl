{{- define "platform-common.pdb" -}}
{{- if (.cfg.pdb | default dict).enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  maxUnavailable: {{ .cfg.pdb.maxUnavailable | default "10%" }}
  selector:
    matchLabels:
      {{- include "platform-common.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end }}
