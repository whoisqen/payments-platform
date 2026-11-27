{{/*
Vault jwt auth mount of the cluster a chart runs in: k8s-<namePrefix>-<env>-<region short>-<component> (tools/config/clusters.py,
written by the vault-config bootstrap from the Argo CD registration). Call with (dict "root" $ "component" "<cell-0|locker|...>").
*/}}
{{- define "platform-common.vaultMount" -}}
{{- $g := .root.Values.global -}}
{{- $prefix := (($g.hyperswitch | default dict).namePrefix) | default "pay" -}}
{{- $rs := regexReplaceAll "^([a-z]{2})-([a-z])[a-z]*-([0-9])$" ($g.region | default "eu-central-1") "${1}${2}${3}" -}}
{{- printf "k8s-%s-%s-%s-%s" $prefix ($g.environment | default "dev") $rs .component -}}
{{- end }}
