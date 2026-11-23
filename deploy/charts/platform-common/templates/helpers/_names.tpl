{{/* Every template takes a dict: root (chart context), cfg (one workload's values), name (resource name), component (label) */}}
{{- define "platform-common.selectorLabels" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "platform-common.labels" -}}
{{ include "platform-common.selectorLabels" . }}
app.kubernetes.io/part-of: payments-platform
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- with (.root.Values.global | default dict).cell }}
payments-platform/cell: {{ . | quote }}
{{- end }}
{{- end }}

{{/* The digest is the only way to name an image; the schema enforces the pattern, this guards renders that bypass it */}}
{{- define "platform-common.image" -}}
{{- $img := .cfg.image | default .root.Values.image -}}
{{- $digest := required "image.digest is required (sha256:<64 hex>)" $img.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
{{- fail "image.digest must match ^sha256:[a-f0-9]{64}$" -}}
{{- end -}}
{{- $registry := required "global.registry is required (registry host and repository prefix, no trailing slash)" (.root.Values.global | default dict).registry -}}
{{- printf "%s/%s@%s" $registry $img.repository $digest -}}
{{- end }}

{{- define "platform-common.serviceAccountName" -}}
{{- (.cfg.serviceAccount | default dict).name | default .name -}}
{{- end }}

{{/* JSON Schema cannot compare two fields, so the replica bounds are checked here */}}
{{- define "platform-common.checkReplicas" -}}
{{- $a := .cfg.autoscaling | default dict -}}
{{- if and $a.enabled (lt (int $a.maxReplicas) (int $a.minReplicas)) -}}
{{- fail (printf "%s: autoscaling.maxReplicas must not be lower than minReplicas" .name) -}}
{{- end -}}
{{- end }}

{{- define "platform-common.scaleTarget" -}}
{{- if eq (.cfg.workload.kind | default "Deployment") "Rollout" -}}
apiVersion: argoproj.io/v1alpha1
kind: Rollout
{{- else -}}
apiVersion: apps/v1
kind: Deployment
{{- end }}
name: {{ .name }}
{{- end }}
