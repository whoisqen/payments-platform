{{- define "platform-common.networkpolicy" -}}
{{- $np := .cfg.networkPolicy | default dict -}}
{{- if $np.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .name }}
  labels:
    {{- include "platform-common.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "platform-common.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - port: http
          protocol: TCP
    {{- with $np.extraIngress }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
    # Sidecar to istiod (xDS) and the egress gateway are the only mesh exits
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
      ports:
        - port: 15012
          protocol: TCP
        - port: 443
          protocol: TCP
    - to:
        - podSelector: {}
    {{- with (.root.Values.global | default dict).dataCidrs }}
    {{- if $np.dataPorts }}
    - to:
        {{- range . }}
        - ipBlock:
            cidr: {{ . }}
        {{- end }}
      ports:
        {{- range $np.dataPorts }}
        - port: {{ . }}
          protocol: TCP
        {{- end }}
    {{- end }}
    {{- end }}
    {{- /* AWS APIs through the interface endpoints (KMS, STS) and the credentials of the EKS Pod Identity agent */ -}}
    {{- if $np.awsEndpoints }}
    {{- with (.root.Values.global | default dict).endpointCidrs }}
    - to:
        {{- range . }}
        - ipBlock:
            cidr: {{ . }}
        {{- end }}
      ports:
        - port: 443
          protocol: TCP
    {{- end }}
    - to:
        - ipBlock:
            cidr: {{ $np.podIdentityAgentCidr | default "169.254.170.23/32" }}
      ports:
        - port: 80
          protocol: TCP
    {{- with (((.root.Values.global | default dict).egress | default dict).sentryCidrs) }}
    # The central Sentry
    - to:
        {{- range . }}
        - ipBlock:
            cidr: {{ . }}
        {{- end }}
      ports:
        - port: 443
          protocol: TCP
    {{- end }}
    {{- end }}
    {{- /* The locker in its own cluster: its pod or load balancer addresses in global.lockerCidrs */ -}}
    {{- if $np.lockerEgress }}
    {{- with (.root.Values.global | default dict).lockerCidrs }}
    - to:
        {{- range . }}
        - ipBlock:
            cidr: {{ . }}
        {{- end }}
      ports:
        - port: {{ $np.lockerPort | default 3001 }}
          protocol: TCP
    {{- end }}
    {{- end }}
    {{- /* PSP APIs on public addresses; the egress firewall allows only the PSP domains (global.egress.pspHosts) */ -}}
    {{- if and $np.pspEgress (((.root.Values.global | default dict).egress | default dict).pspHosts) }}
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16]
      ports:
        - port: 443
          protocol: TCP
    {{- end }}
    {{- /* The webhook egress gateway (deploy/platform/istio/egress), HTTP CONNECT over mutual TLS */ -}}
    {{- if $np.webhookEgress }}
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-egress
          podSelector:
            matchLabels:
              istio: egressgateway
      ports:
        - port: 8080
          protocol: TCP
    {{- end }}
    {{- with $np.extraEgress }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
{{- end }}
