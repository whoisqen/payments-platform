{{- define "platform-common.serviceaccount" -}}
{{- if (.cfg.serviceAccount | default dict).create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "platform-common.serviceAccountName" . }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
    {{- with .cfg.serviceAccount.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
automountServiceAccountToken: false
{{- end }}
{{- end }}
