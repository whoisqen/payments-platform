{{/* card-vault reads LOCKER__<SECTION>__<KEY> (config crate, prefix LOCKER, separator "__", keys lower-cased) */}}
{{- define "locker.flatten" -}}
{{- $prefix := .prefix -}}
{{- range $k, $v := .value }}
{{- $key := printf "%s__%s" $prefix (upper $k) }}
{{- if kindIs "map" $v }}
{{ include "locker.flatten" (dict "prefix" $key "value" $v) }}
{{- else if not (kindIs "invalid" $v) }}
{{ $key }}: {{ $v | toString | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/* Non-secret settings as env; secret settings come from the ExternalSecret "locker.secretName" */}}
{{- define "locker.configEnv" -}}
{{- $config := deepCopy .Values.config -}}
{{- $_ := set $config.server "port" .Values.container.port -}}
{{- if eq $config.metrics.mode "prometheus" }}
{{- $metricsPort := 0 -}}
{{- range .Values.container.extraPorts }}{{ if eq .name "metrics" }}{{ $metricsPort = .port }}{{ end }}{{ end -}}
{{- if not $metricsPort }}{{ fail "container.extraPorts needs a port named metrics for config.metrics.mode prometheus" }}{{ end -}}
{{- $_ := set $config.metrics "port" $metricsPort -}}
{{- end }}
{{- $tenants := dict -}}
{{- range .Values.tenants }}
{{- $_ := set $tenants .id (dict "schema" .schema "redis_key_prefix" .redisKeyPrefix) -}}
{{- end }}
{{- $_ := set $config "tenant_secrets" $tenants -}}
{{- include "locker.flatten" (dict "prefix" "LOCKER" "value" $config) }}
{{- with .Values.postgresTls }}
PGSSLMODE: {{ .mode | quote }}
PGSSLROOTCERT: {{ .rootCert | quote }}
{{- end }}
{{- end }}

{{- define "locker.secretName" -}}
{{- .Values.externalSecret.name | default "locker-secrets" -}}
{{- end }}

{{- define "locker.vaultKey" -}}
{{- $env := required "global.environment is required for the Vault paths of the locker" (.root.Values.global | default dict).environment -}}
{{- printf "%s/%s/%s" $env .root.Values.externalSecret.pathPrefix .path -}}
{{- end }}
