{{- define "platform-common.authorizationpolicy" -}}
{{- $ap := (.cfg.istio | default dict).authorizationPolicy | default dict -}}
{{- if $ap.enabled }}
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "platform-common.selectorLabels" . | nindent 6 }}
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              {{- toYaml $ap.principals | nindent 14 }}
{{- end }}
{{- end }}
