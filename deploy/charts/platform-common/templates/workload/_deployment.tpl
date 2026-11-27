{{- define "platform-common.deployment" -}}
{{- $w := .cfg.workload -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
  {{- with $w.syncWave }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ . | quote }}
  {{- end }}
spec:
  {{- /* the HPA or ScaledObject owns the replica count when autoscaling is on */}}
  {{- if not (include "platform-common.scaled" .) }}
  replicas: {{ $w.replicas | default 1 }}
  {{- end }}
  minReadySeconds: {{ $w.minReadySeconds | default 10 }}
  progressDeadlineSeconds: {{ $w.progressDeadlineSeconds | default 600 }}
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      {{- include "platform-common.selectorLabels" . | nindent 6 }}
  strategy:
    {{- if eq $w.strategy.type "Recreate" }}
    type: Recreate
    {{- else }}
    type: RollingUpdate
    rollingUpdate:
      maxSurge: {{ $w.strategy.maxSurge | default "25%" }}
      maxUnavailable: {{ $w.strategy.maxUnavailable | default 0 }}
    {{- end }}
  template:
    {{- include "platform-common.podTemplate" . | nindent 4 }}
{{- end }}
