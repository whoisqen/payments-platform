# Tasks: NNN-slug

Every item is one unit of work for one agent. The `id` becomes the commit trailer `Spec: specs/NNN-slug#Tn`; `issue` is a GitHub issue in the specification's milestone, created after the approval (`none` until then).

```yaml
- id: T1
  title: Short imperative title
  agent: terraform-engineer
  paths: ["infra/modules/example/**"]
  depends_on: []
  provides: output example_arn
  requires: []
  acceptance: terraform test passes; plan shows only the new module
  issue: none             # "#123" once created
```
