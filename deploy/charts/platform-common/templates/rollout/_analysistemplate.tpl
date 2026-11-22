{{- define "platform-common.analysistemplate" -}}
{{- $an := .cfg.workload.analysis -}}
{{- if and (eq (.cfg.workload.kind | default "Deployment") "Rollout") $an }}
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  metrics:
    - name: error-rate-5xx
      interval: 1m
      failureLimit: 0
      successCondition: result[0] < {{ $an.maxErrorRate }}
      provider:
        prometheus:
          address: {{ $an.prometheusAddress }}
          query: |
            (sum(rate(istio_requests_total{destination_service_name="{{ .name }}-canary",response_code=~"5.."}[5m]))
            / sum(rate(istio_requests_total{destination_service_name="{{ .name }}-canary"}[5m]))) or on() vector(0)
    - name: p99-latency-delta-ms
      interval: 1m
      failureLimit: 0
      successCondition: result[0] < {{ $an.maxP99DeltaMs }}
      provider:
        prometheus:
          address: {{ $an.prometheusAddress }}
          query: |
            (histogram_quantile(0.99, sum by (le) (rate(istio_request_duration_milliseconds_bucket{destination_service_name="{{ .name }}-canary"}[5m])))
            - histogram_quantile(0.99, sum by (le) (rate(istio_request_duration_milliseconds_bucket{destination_service_name="{{ .name }}"}[5m])))) or on() vector(0)
    {{- if $an.authorizationRate }}
    # Metric name is a contract with observability/; the canary may lose at most 0.5 percentage points
    - name: authorization-rate-delta
      interval: 1m
      failureLimit: 0
      successCondition: result[0] > -0.005
      provider:
        prometheus:
          address: {{ $an.prometheusAddress }}
          query: |
            (avg(payments_authorization_rate{service="{{ .name }}-canary"})
            - avg(payments_authorization_rate{service="{{ .name }}"})) or on() vector(0)
    {{- end }}
{{- end }}
{{- end }}
