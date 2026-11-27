{{- define "platform-common.hpa" -}}
{{- $a := .cfg.autoscaling }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    {{- include "platform-common.scaleTarget" . | nindent 4 }}
  minReplicas: {{ $a.minReplicas }}
  maxReplicas: {{ $a.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $a.targetCPU }}
    {{- with $a.rpsPerPod }}
    # Served by Prometheus Adapter; 70% of the pod capacity leaves room for pod start-up
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: {{ . | quote }}
    {{- end }}
  behavior:
    {{- include "platform-common.hpaBehavior" . | nindent 4 }}
{{- end }}

{{- define "platform-common.hpaBehavior" -}}
scaleUp:
  stabilizationWindowSeconds: 0
  policies:
    - type: Percent
      value: 100
      periodSeconds: 15
scaleDown:
  stabilizationWindowSeconds: 600
  policies:
    - type: Percent
      value: 10
      periodSeconds: 60
{{- end }}
