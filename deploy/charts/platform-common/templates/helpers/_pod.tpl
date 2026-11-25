{{- define "platform-common.probe" -}}
httpGet:
  path: {{ .p.path }}
  port: http
periodSeconds: {{ .p.periodSeconds | default 10 }}
timeoutSeconds: {{ .p.timeoutSeconds | default 2 }}
failureThreshold: {{ .p.failureThreshold | default 3 }}
{{- end }}

{{- define "platform-common.podTemplate" -}}
{{- $cfg := .cfg -}}
{{- $life := $cfg.lifecycle | default dict -}}
{{- $sched := $cfg.scheduling | default dict -}}
{{- $istio := $cfg.istio | default dict -}}
{{- $warm := $cfg.warmup | default dict -}}
{{- $inject := true -}}
{{- if hasKey $istio "inject" -}}{{- $inject = $istio.inject -}}{{- end -}}
metadata:
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
  annotations:
    sidecar.istio.io/inject: {{ ternary "true" "false" $inject | quote }}
spec:
  serviceAccountName: {{ include "platform-common.serviceAccountName" . }}
  automountServiceAccountToken: false
  terminationGracePeriodSeconds: {{ $life.terminationGracePeriodSeconds | default 60 }}
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  {{- with $sched.nodePool }}
  nodeSelector:
    karpenter.sh/nodepool: {{ . }}
  {{- end }}
  {{- with $sched.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  topologySpreadConstraints:
    # Three AZs are the unit of failure (D6), so zones are a hard constraint and hosts a soft one
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          {{- include "platform-common.selectorLabels" . | nindent 10 }}
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          {{- include "platform-common.selectorLabels" . | nindent 10 }}
  containers:
    - name: {{ .root.Chart.Name }}
      image: {{ include "platform-common.image" . | quote }}
      imagePullPolicy: {{ ($cfg.image | default .root.Values.image).pullPolicy | default "IfNotPresent" }}
      {{- with $cfg.container.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $cfg.container.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      ports:
        - name: http
          containerPort: {{ $cfg.container.port }}
          protocol: TCP
        {{- range $cfg.container.extraPorts }}
        - name: {{ .name }}
          containerPort: {{ .port }}
          protocol: TCP
        {{- end }}
      env:
        {{- range $k, $v := $cfg.container.env }}
        - name: {{ $k }}
          value: {{ $v | quote }}
        {{- end }}
        {{- if $warm.enabled }}
        # The readiness endpoint opens at the ratio or when the wait ends; the application owns that fallback (D8)
        - name: CACHE_WARM_MIN_RATIO
          value: {{ $warm.minRatio | quote }}
        - name: CACHE_WARM_MAX_WAIT_SECONDS
          value: {{ $warm.maxWaitSeconds | quote }}
        {{- end }}
      {{- $dsn := $cfg.container.sentryDsn | default dict }}
      {{- if or $cfg.container.envFromSecrets $dsn.envName }}
      envFrom:
        {{- range $cfg.container.envFromSecrets }}
        - secretRef:
            name: {{ . }}
        {{- end }}
        {{- if $dsn.envName }}
        # Optional: the service starts without the Sentry DSN and reports no errors until the secret exists
        - secretRef:
            name: {{ .name }}-sentry-dsn
            optional: true
        {{- end }}
      {{- end }}
      resources:
        {{- toYaml $cfg.container.resources | nindent 8 }}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      startupProbe:
        {{- include "platform-common.probe" (dict "p" $cfg.probes.startup) | nindent 8 }}
      livenessProbe:
        {{- include "platform-common.probe" (dict "p" $cfg.probes.liveness) | nindent 8 }}
      readinessProbe:
        {{- include "platform-common.probe" (dict "p" $cfg.probes.readiness) | nindent 8 }}
      lifecycle:
        preStop:
          # Native sleep because the distroless image has no shell; endpoints drain before SIGTERM
          sleep:
            seconds: {{ $life.preStopSeconds | default 15 }}
      volumeMounts:
        - name: tmp
          mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
{{- end }}
