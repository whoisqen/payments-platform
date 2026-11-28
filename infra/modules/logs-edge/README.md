# logs-edge

Entry of the central logs (shared-services): the TLS server identity of Logstash and the private name of `central.logs_otlp_endpoint`.

- ECDSA P-256 key and CSR (`hashicorp/tls`), certificate from the private CA of shared-services (`aws_acmpca_certificate`, `EndEntityServerAuthCertificate/V1`, `validity_days` 365).
- Secret `<prefix>/shared-services/logstash/tls` (shared key): `tls.crt` (certificate and chain), `tls.key` (PKCS#8), `ca.crt` (the CA that also signs the collector client certificates). External Secrets reads it (`deploy/platform/central-tls`).
- Rotation: `time_rotating` (`rotation_days` 300) replaces the key, so the first apply after that writes a new version; no person handles the key, which lives only in the KMS-encrypted state and the secret.
- Private zone of the host alone, attached to `vpc_ids`. Second step (`nlb_lookup_enabled = true`): alias A record to the NLB tagged `service.k8s.aws/stack = nlb_stack_tag`.
