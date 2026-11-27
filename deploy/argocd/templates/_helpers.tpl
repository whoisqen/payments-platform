{{/* The region short name the ApplicationSets compute from the region directory: eu-central-1 -> euc1 */}}
{{- define "argocd-bootstrap.regionShort" -}}
{{- regexReplaceAll "^([a-z]{2})-([a-z])[a-z]*-([0-9])$" . "${1}${2}${3}" -}}
{{- end }}

{{/* Argo CD cluster name, the destination.name of the ApplicationSets: <namePrefix>-<env>-<region short>-<component> */}}
{{- define "argocd-bootstrap.clusterName" -}}
{{- printf "%s-%s-%s-%s" .prefix .cluster.environment (include "argocd-bootstrap.regionShort" .cluster.region) .cluster.component -}}
{{- end }}
