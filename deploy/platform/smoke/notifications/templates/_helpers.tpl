{{/* Expression list such as ['dev', 'stage'] */}}
{{- define "notifications.envList" -}}
{{- $q := list -}}
{{- range .Values.environments -}}{{- $q = append $q (printf "'%s'" .) -}}{{- end -}}
{{- printf "[%s]" (join ", " $q) -}}
{{- end }}

{{/* Label selector value such as (dev,stage) */}}
{{- define "notifications.envSelector" -}}
{{- printf "(%s)" (join "," .Values.environments) -}}
{{- end }}
