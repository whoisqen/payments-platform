{{- define "platform-common.rollout" -}}
{{- $w := .cfg.workload -}}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
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
  {{- if not (.cfg.autoscaling | default dict).enabled }}
  replicas: {{ $w.replicas | default 1 }}
  {{- end }}
  minReadySeconds: {{ $w.minReadySeconds | default 10 }}
  progressDeadlineSeconds: {{ $w.progressDeadlineSeconds | default 600 }}
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      {{- include "platform-common.selectorLabels" . | nindent 6 }}
  strategy:
    canary:
      stableService: {{ .name }}
      canaryService: {{ .name }}-canary
      trafficRouting:
        istio:
          virtualService:
            name: {{ .name }}
            routes:
              - primary
      steps:
        {{- range $w.strategy.weights }}
        - setWeight: {{ . }}
        - pause:
            duration: {{ $w.strategy.pauseDuration | default "10m" }}
        {{- end }}
      {{- if $w.analysis }}
      analysis:
        startingStep: 1
        templates:
          - templateName: {{ .name }}
      {{- end }}
  template:
    {{- include "platform-common.podTemplate" . | nindent 4 }}
{{- end }}
