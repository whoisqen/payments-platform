{{- define "platform-common.scaledobject" -}}
{{- $a := .cfg.autoscaling | default dict }}
{{- $w := (.root.Values.global | default dict).workingHours | default dict }}
{{- $hours := include "platform-common.workingHours" . }}
{{- $min := $a.minReplicas }}
{{- $max := $a.maxReplicas }}
{{- if not $a.enabled }}
{{- $min = .cfg.workload.replicas | default 1 }}
{{- $max = $min }}
{{- end }}
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    {{- include "platform-common.scaleTarget" . | nindent 4 }}
  minReplicaCount: {{ if $hours }}0{{ else }}{{ $min }}{{ end }}
  maxReplicaCount: {{ $max }}
  pollingInterval: {{ $a.pollingInterval | default 15 }}
  cooldownPeriod: {{ $a.cooldownPeriod | default 300 }}
  {{- if and $a.enabled (ne $a.kind "keda") }}
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        {{- include "platform-common.hpaBehavior" . | nindent 8 }}
  {{- end }}
  triggers:
    {{- if $hours }}
    # Holds the floor inside the working window; outside it no other trigger is active and the workload scales to zero
    - type: cron
      metadata:
        timezone: {{ $w.timezone | quote }}
        start: {{ $w.start | quote }}
        end: {{ $w.end | quote }}
        desiredReplicas: {{ $min | quote }}
    {{- end }}
    {{- if and $a.enabled (eq $a.kind "keda") }}
    {{- toYaml $a.triggers | nindent 4 }}
    {{- else if $a.enabled }}
    - type: cpu
      metricType: Utilization
      metadata:
        value: {{ $a.targetCPU | quote }}
    {{- end }}
{{- end }}
