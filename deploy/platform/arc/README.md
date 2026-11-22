# arc

Actions Runner Controller on the shared-services cluster.
- `applicationset.yaml`: controller, three scale sets (ci-prod, ci-stage, ci-pr) and `config/`.
- `values-*.yaml`: upstream chart values; runner images are digest placeholders.
- `config/`: namespaces, PriorityClasses, service accounts, ExternalSecrets, ci-pr NetworkPolicy.
- Replace every `REPLACE_*` value before sync; no secrets live here.
