{{- define "platform-common.servicemonitor" -}}
{{- $sm := .cfg.serviceMonitor | default dict -}}
{{- if $sm.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  selector:
    matchLabels:
      {{- include "platform-common.selectorLabels" . | nindent 6 }}
      payments-platform/role: stable
  endpoints:
    - port: {{ $sm.port | default "http" }}
      path: {{ $sm.path | default "/metrics" }}
      interval: {{ $sm.interval | default "30s" }}
{{- end }}
{{- end }}
