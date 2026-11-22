{{- define "platform-common.destinationrule" -}}
{{- if (.cfg.service | default dict).enabled }}
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  host: {{ .name }}
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    connectionPool:
      http:
        http1MaxPendingRequests: {{ .cfg.service.maxPendingRequests | default 100 }}
    # Section 24.4: eject a pod after 5 consecutive errors for 30 s
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
{{- end }}
{{- end }}
