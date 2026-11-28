
{{- define "logstash.labels" -}}
{{ include "platform-common.labels" (dict "root" . "cfg" .Values "name" "logstash" "component" "logstash") }}
{{- end }}

{{- define "logstash.selectorLabels" -}}
{{ include "platform-common.selectorLabels" (dict "root" . "component" "logstash") }}
{{- end }}

{{/* The infra outputs and the values derived from config/platform.yaml must be set; a placeholder deploy would drop logs */}}
{{- define "logstash.required" -}}
{{- $_ := required "global.registry is required (ECR host and repository prefix)" .Values.global.registry -}}
{{- $_ := required "opensearch.endpoint is required (VPC endpoint host of the domain)" .Values.opensearch.endpoint -}}
{{- $_ := required "opensearch.region is required" .Values.opensearch.region -}}
{{- $_ := required "serviceAccount.roleArn is required (IRSA role of infra/modules/log-ingestion)" .Values.serviceAccount.roleArn -}}
{{- if .Values.gateway.enabled -}}
{{- $_ := required "gateway.hostname is required (host of central.logs_otlp_endpoint)" .Values.gateway.hostname -}}
{{- end -}}
{{- end }}
