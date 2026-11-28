# opensearch-dashboards

- Publishes OpenSearch Dashboards of the central domain at `central.opensearch.dashboards_host` through the internal admin Gateway (`istio-ingress-admin/admin`, listener `https`). Only `/_dashboards` is routed; `/` redirects there; the REST API of the domain is not published.
- Backend: Service `opensearch-dashboards` (ExternalName to the VPC endpoint of the domain) and a BackendTLSPolicy: the gateway opens TLS with SNI `dashboards_host` and checks the certificate against the admin private CA (`caBundle`).
- Domain side (infra): a custom endpoint equal to `dashboards_host` with an ACM certificate issued by the admin private CA, and SAML (Okta) configured on that endpoint, so the SAML redirects use the admin host. No oauth2-proxy: Dashboards signs people in itself.
- Values come from the add-on `central/admin/opensearch-dashboards` (`central.opensearch` of the Argo CD values); an empty value fails the render.
