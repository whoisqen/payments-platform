# central-tls

- One ExternalSecret: the client certificate, key and CA of the mutual TLS to the central stack, read from `<namePrefix>/shared-services/otel-collector/tls`.
- Used by the `kube-prometheus` add-on (`prometheus-central-tls`) and the `otel-collector` add-on (`otel-collector-tls`); each ApplicationSet passes `secretName` and `namePrefix`.
