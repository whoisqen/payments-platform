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
    {{- with $np.extraEgress }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
{{- end }}
