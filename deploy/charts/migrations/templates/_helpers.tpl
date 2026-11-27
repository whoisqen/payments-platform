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
- name: AWS_REGION
  value: {{ required "global.region is required (IAM authentication and the snapshot)" ((.Values.global | default dict).region) | quote }}
{{- end }}

{{/* The snapshot target of the init container, derived from the naming convention unless set */}}
{{- define "migrations.snapshotEnv" -}}
{{- $s := .Values.snapshot -}}
{{- $g := .Values.global | default dict -}}
{{- $prefix := (($g.hyperswitch | default dict).namePrefix) | default "pay" -}}
{{- $env := $g.environment | default "" -}}
{{- $region := $g.region | default "" -}}
{{- $rs := regexReplaceAll "^([a-z]{2})-([a-z])[a-z]*-([0-9])$" $region "${1}${2}${3}" -}}
{{- $arn := $s.resourceArn -}}
{{- if not $arn -}}
{{- $component := $s.auroraComponent -}}
{{- if not $component }}{{ $component = printf "aurora-%s" (required "global.cell or snapshot.auroraComponent is required" $g.cell) }}{{ end -}}
{{- $arn = printf "arn:aws:rds:%s:%s:cluster:%s-%s-%s-%s" $region (required "global.accountId is required for the snapshot ARN" $g.accountId | toString) $prefix (required "global.environment is required" $env) $rs $component -}}
{{- end -}}
{{- $vault := $s.vault | default (printf "%s-%s-%s-backup" $prefix $env $rs) }}
- name: SNAPSHOT_RESOURCE_ARN
  value: {{ $arn | quote }}
- name: SNAPSHOT_VAULT
  value: {{ $vault | quote }}
- name: SNAPSHOT_ROLE_ARN
  value: {{ $s.roleArn | quote }}
{{- end }}

{{- define "migrations.caMount" -}}
- name: rds-ca
  mountPath: {{ .Values.rdsCaBundle.mountPath }}
  readOnly: true
{{- end }}

{{- define "migrations.caVolume" -}}
- name: rds-ca
  configMap:
    name: {{ .Values.rdsCaBundle.configMapName }}
    items:
      - key: global-bundle.pem
        path: global-bundle.pem
{{- end }}
