{{- define "platform-common.scaledobject" -}}
{{- $a := .cfg.autoscaling }}
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    {{- include "platform-common.scaleTarget" . | nindent 4 }}
  minReplicaCount: {{ $a.minReplicas }}
  maxReplicaCount: {{ $a.maxReplicas }}
  pollingInterval: {{ $a.pollingInterval | default 15 }}
  cooldownPeriod: {{ $a.cooldownPeriod | default 300 }}
  triggers:
    {{- toYaml $a.triggers | nindent 4 }}
{{- end }}
