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

{{/* The digest names an image; a tag is accepted only on a local cluster, whose images are loaded without a registry digest */}}
{{- define "platform-common.image" -}}
{{- $img := .cfg.image | default .root.Values.image -}}
{{- $registry := required "global.registry is required (registry host and repository prefix, no trailing slash)" (.root.Values.global | default dict).registry -}}
{{- if and (not $img.digest) $img.tag (not (include "platform-common.localCluster" .root)) -}}
{{- fail "image.tag without a digest is accepted only with global.localCluster: true; name the image by digest" -}}
{{- end -}}
{{- if and (not $img.digest) $img.tag -}}
{{- printf "%s/%s:%s" $registry $img.repository $img.tag -}}
{{- else -}}
{{- $digest := required "image.digest is required (sha256:<64 hex>)" $img.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
{{- fail "image.digest must match ^sha256:[a-f0-9]{64}$" -}}
{{- end -}}
{{- printf "%s/%s@%s" $registry $img.repository $digest -}}
{{- end -}}
{{- end }}

{{/* Non-empty when global.localCluster is true: the kind stack of deploy/local, which has no AWS behind it */}}
{{- define "platform-common.localCluster" -}}
{{- if (.Values.global | default dict).localCluster }}true{{ end -}}
{{- end }}

{{/* Fails unless global.localCluster is true; guards settings that only a local cluster may relax */}}
{{- define "platform-common.requireLocal" -}}
{{- if not (include "platform-common.localCluster" .root) -}}
{{- fail (printf "%s is allowed only with global.localCluster: true" .what) -}}
{{- end -}}
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
