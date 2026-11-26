
{{/* Fails a render that still carries a REPLACE_* placeholder once the environment layer sets requireResolved */}}
{{- define "ratelimit.guard" -}}
{{- if .Values.requireResolved -}}
{{- if contains "REPLACE_" (toYaml .Values) -}}
{{- fail "unresolved REPLACE_* placeholder in values" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* The registry is the platform ECR; the digest is the only way to name the image */}}
{{- define "ratelimit.image" -}}
{{- include "platform-common.image" (dict "root" . "cfg" .Values) -}}
{{- end }}

{{/* One request_class descriptor per class; takes limits, classes, shadow, where; fails on a missing class, bad unit or bad count */}}
{{- define "ratelimit.classEntries" -}}
{{- $out := list -}}
{{- range $.classes -}}
{{- $class := . -}}
{{- $l := index $.limits $class | default dict -}}
{{- if not $l -}}{{- fail (printf "%s: no limit for request class %s" $.where $class) -}}{{- end -}}
{{- if not (has $l.unit (list "second" "minute" "hour" "day")) -}}
{{- fail (printf "%s: unit of %s must be second, minute, hour or day" $.where $class) -}}
{{- end -}}
{{- if not (or (kindIs "float64" $l.requestsPerUnit) (kindIs "int64" $l.requestsPerUnit)) -}}{{- fail (printf "%s: requestsPerUnit of %s must be a number" $.where $class) -}}{{- end -}}
{{- $n := int64 $l.requestsPerUnit -}}
{{- if lt $n 1 -}}{{- fail (printf "%s: requestsPerUnit of %s must be at least 1" $.where $class) -}}{{- end -}}
{{- $rl := dict "unit" $l.unit "requests_per_unit" $n -}}
{{- if $.shadow -}}{{- $_ := set $rl "shadow_mode" true -}}{{- end -}}
{{- $out = append $out (dict "key" "request_class" "value" $class "rate_limit" $rl) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}

{{/* Descriptor tree: named merchants first, then the wildcard merchant with the defaults */}}
{{- define "ratelimit.config" -}}
{{- $rl := .Values.rateLimit -}}
{{- $classes := $rl.requestClasses -}}
{{- $shadow := $rl.shadowMode -}}
{{- range $tier, $limits := $rl.tiers -}}
{{- $_ := include "ratelimit.classEntries" (dict "limits" $limits "classes" $classes "shadow" $shadow "where" (printf "tier %s" $tier)) -}}
{{- end -}}
{{- $descs := list -}}
{{- $seen := dict -}}
{{- range $i, $o := $rl.overrides -}}
{{- if not (regexMatch "^[A-Za-z0-9_-]{1,64}$" ($o.name | default "" | toString)) -}}
{{- fail (printf "overrides[%d]: name must match ^[A-Za-z0-9_-]{1,64}$" $i) -}}
{{- end -}}
{{- if hasKey $seen (printf "name/%s" $o.name) -}}{{- fail (printf "overrides[%d]: duplicate name %s" $i $o.name) -}}{{- end -}}
{{- $_ := set $seen (printf "name/%s" $o.name) true -}}
{{- if not $o.rateKeys -}}{{- fail (printf "overrides[%d]: rateKeys must list at least one rate key" $i) -}}{{- end -}}
{{- $base := $rl.defaults -}}
{{- if $o.tier -}}
{{- if not (hasKey $rl.tiers $o.tier) -}}{{- fail (printf "overrides[%d]: unknown tier %s" $i $o.tier) -}}{{- end -}}
{{- $base = index $rl.tiers $o.tier -}}
{{- end -}}
{{- $own := $o.limits | default dict -}}
{{- range $class, $_ := $own -}}
{{- if not (has $class $classes) -}}{{- fail (printf "overrides[%d]: unknown request class %s" $i $class) -}}{{- end -}}
{{- end -}}
{{- $limits := mergeOverwrite (deepCopy $base) (deepCopy $own) -}}
{{- $entries := include "ratelimit.classEntries" (dict "limits" $limits "classes" $classes "shadow" $shadow "where" (printf "override %s" $o.name)) | fromYamlArray -}}
{{- range $k := $o.rateKeys -}}
{{- if not (regexMatch "^[0-9a-f]{16}$" ($k | toString)) -}}
{{- fail (printf "overrides[%d]: rate key %v must be 16 lower-case hex digits" $i $k) -}}
{{- end -}}
{{- if hasKey $seen $k -}}{{- fail (printf "overrides[%d]: rate key %s is already in another override" $i $k) -}}{{- end -}}
{{- $_ := set $seen $k true -}}
{{- $descs = append $descs (dict "key" "merchant" "value" $k "descriptors" $entries) -}}
{{- end -}}
{{- end -}}
{{- $default := include "ratelimit.classEntries" (dict "limits" $rl.defaults "classes" $classes "shadow" $shadow "where" "defaults") | fromYamlArray -}}
{{- $descs = append $descs (dict "key" "merchant" "descriptors" $default) -}}
{{- toYaml (dict "domain" $rl.domain "descriptors" $descs) -}}
{{- end }}
