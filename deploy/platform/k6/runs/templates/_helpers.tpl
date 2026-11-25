{{/* Load generation exists only on stage: any other environment fails the render instead of syncing a quiet no-op */}}
{{- define "k6.checkStage" -}}
{{- if ne .Values.global.environment "stage" -}}
{{- fail (printf "k6-runs renders only for stage, got global.environment=%q" .Values.global.environment) -}}
{{- end -}}
{{- if .Values.requireResolved -}}
{{- range $k, $v := dict "global.registry" .Values.global.registry "target.baseUrl" .Values.target.baseUrl "remoteWrite.url" .Values.remoteWrite.url -}}
{{- if hasPrefix "REPLACE_" $v -}}{{- fail (printf "%s is not resolved" $k) -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if regexMatch "(?i)prod|cde" (urlParse .Values.target.baseUrl).host -}}
{{- fail "target.baseUrl looks like a prod or CDE host" -}}
{{- end -}}
{{- end }}

{{- define "k6.labels" -}}
{{ include "platform-common.labels" (dict "root" .root "component" .component) }}
{{- end }}

{{- define "k6.image" -}}
{{- $img := index .Values.images .name -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $img.digest) -}}{{- fail (printf "images.%s.digest must match ^sha256:[a-f0-9]{64}$" .name) -}}{{- end -}}
{{- printf "%s/%s:%s@%s" .Values.global.registry $img.repository $img.tag $img.digest -}}
{{- end }}

{{/* ConfigMap keys cannot hold a slash; the projected volume maps each key back to its path, so relative imports keep working */}}
{{- define "k6.scriptKey" -}}
{{- . | trimPrefix "scripts/" | replace "/" "_" -}}
{{- end }}

{{- define "k6.scriptFiles" -}}
{{- range $p, $_ := .Files.Glob "scripts/load/{lib,scenarios}/*.js" }}
- {{ $p }}
{{- end }}
{{- range $p, $_ := .Files.Glob "scripts/chaos/*.js" }}
- {{ $p }}
{{- end }}
{{- end }}

{{/* Script variables travel as -e flags: the initializer runs k6 inspect, which does not read the pod environment, and the guard in the scripts runs at init */}}
{{- define "k6.arguments" -}}
{{- $v := .root.Values -}}
{{- $args := list "--out experimental-prometheus-rw" "--tag testid=__RUN__" (printf "--tag scenario=%s" .name) (printf "--tag environment=%s" $v.global.environment) -}}
{{- $env := dict "TARGET_ENV" $v.global.environment "BASE_URL" $v.target.baseUrl "FREEZE" (toString $v.target.freeze) "OPEN_INCIDENTS" "0" -}}
{{- $env = merge $env (deepCopy (.env | default dict)) -}}
{{- range $k := keys $env | sortAlpha -}}
{{- $args = append $args (printf "-e %s=%s" $k (index $env $k)) -}}
{{- end -}}
{{- join " " $args -}}
{{- end }}

{{- define "k6.securityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 12345
  runAsGroup: 12345
  seccompProfile:
    type: RuntimeDefault
containerSecurityContext:
  allowPrivilegeEscalation: false
  # The operator's initializer writes the archive of the script next to it in the working directory
  readOnlyRootFilesystem: false
  capabilities:
    drop: [ALL]
{{- end }}

{{/* Shared by initializer, runner and starter: the initializer runs the init code too, so it needs the same env, secret and scripts */}}
{{- define "k6.podSpec" -}}
{{- $root := .root -}}
metadata:
  labels:
    app.kubernetes.io/part-of: payments-platform
    payments-platform/scenario: {{ .scenario }}
  annotations:
    sidecar.istio.io/inject: "false"
    karpenter.sh/do-not-disrupt: "true"
image: {{ include "k6.image" (dict "Values" $root.Values "name" .image) | quote }}
# The k6 CRD types this field as a string
automountServiceAccountToken: "false"
nodeSelector:
  karpenter.sh/nodepool: {{ $root.Values.placement.nodePool }}
tolerations:
  {{- toYaml $root.Values.placement.tolerations | nindent 2 }}
{{ include "k6.securityContext" . }}
{{- if .withScripts }}
env:
  - name: K6_PROMETHEUS_RW_SERVER_URL
    value: {{ $root.Values.remoteWrite.url | quote }}
  - name: K6_PROMETHEUS_RW_TREND_STATS
    value: {{ $root.Values.remoteWrite.trendStats | quote }}
  - name: K6_PROMETHEUS_RW_PUSH_INTERVAL
    value: {{ $root.Values.remoteWrite.pushInterval | quote }}
envFrom:
  - secretRef:
      name: {{ $root.Values.credentials.secretName }}
volumes:
  - name: scripts
    projected:
      sources:
        - configMap:
            name: k6-scripts
            items:
              {{- range (include "k6.scriptFiles" $root | fromYamlArray) }}
              - key: {{ include "k6.scriptKey" . }}
                path: {{ trimPrefix "scripts/" . }}
              {{- end }}
  - name: tmp
    emptyDir: {}
volumeMounts:
  - name: scripts
    mountPath: /scripts
    readOnly: true
  - name: tmp
    mountPath: /tmp
{{- end }}
{{- end }}
