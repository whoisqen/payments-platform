{{/* Canary Service and Istio VirtualService; Argo Rollouts edits the route weights in place */}}
{{- define "platform-common.canary" -}}
{{- if eq (.cfg.workload.kind | default "Deployment") "Rollout" }}
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}-canary
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
    payments-platform/role: canary
spec:
  selector:
    {{- include "platform-common.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .cfg.service.port }}
      targetPort: http
      protocol: TCP
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  hosts:
    - {{ .name }}
  http:
    - name: primary
      route:
        - destination:
            host: {{ .name }}
          weight: 100
        - destination:
            host: {{ .name }}-canary
          weight: 0
{{- end }}
{{- end }}
