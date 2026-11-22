{{- define "platform-common.service" -}}
{{- if (.cfg.service | default dict).enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
    payments-platform/role: stable
spec:
  selector:
    {{- include "platform-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .cfg.service.port }}
      targetPort: http
      protocol: TCP
{{- end }}
{{- end }}
