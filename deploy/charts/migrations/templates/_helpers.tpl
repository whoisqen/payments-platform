{{- define "migrations.labels" -}}
{{- include "platform-common.labels" (dict "root" . "name" "migrations" "component" "migrations") -}}
{{- end }}

{{/* The Job object carries component migration, which Kyverno require-migration-snapshot matches; its pods keep component migrations for the NetworkPolicy */}}
{{- define "migrations.jobLabels" -}}
{{- include "platform-common.labels" (dict "root" . "name" "migrations" "component" "migration") -}}
{{- end }}

{{- define "migrations.hook" -}}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: {{ .weight | quote }}
helm.sh/hook-delete-policy: before-hook-creation
{{- end }}

{{- define "migrations.image" -}}
{{- include "platform-common.image" (dict "root" . "cfg" .Values) -}}
{{- end }}

{{- define "migrations.podSecurity" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{- define "migrations.containerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
{{- end }}

{{- define "migrations.env" -}}
- name: PGHOST
  value: {{ .Values.database.host | quote }}
- name: PGPORT
  value: {{ .Values.database.port | quote }}
- name: PGDATABASE
  value: {{ .Values.database.name | quote }}
- name: PGUSER
  value: {{ .Values.database.user | quote }}
- name: PGSSLMODE
  value: verify-full
{{- end }}
