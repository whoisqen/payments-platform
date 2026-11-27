{{/* The digest: images.kafka-admin of the environment's images.yaml (CI-written) wins over image.digest */}}
{{- define "kafka-topics.digest" -}}
{{- (index (.Values.images | default dict) "kafka-admin") | default .Values.image.digest -}}
{{- end }}

{{/* Renders only with a real image digest and brokers, like the smoke Job */}}
{{- define "kafka-topics.enabled" -}}
{{- if and .Values.brokers (not (hasPrefix "REPLACE_" .Values.image.repository)) (not (regexMatch "^sha256:0+$" (include "kafka-topics.digest" .))) -}}true{{- end -}}
{{- end }}

{{- define "kafka-topics.labels" -}}
app.kubernetes.io/name: kafka-topics
app.kubernetes.io/part-of: payments-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* The topic names, from the same map the router uses */}}
{{- define "kafka-topics.names" -}}
{{- $names := list -}}
{{- range $_, $event := include "platform-common.hyperswitch.topics" (dict) | fromYaml -}}
{{- $names = append $names (printf "%s-%s-events" $.Values.topicPrefix $event) -}}
{{- end -}}
{{- toYaml (sortAlpha $names) -}}
{{- end }}
