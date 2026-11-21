---
name: new-cell
description: Add a new cell with no manual steps.
---

# new-cell

- Add `deploy/envs/<env>/<region>/<cell>/` (values, Aurora and MemoryDB capacity profile, NodePool limits); ArgoCD ApplicationSets pick it up with no manual steps.
- Add alerts and dashboards for the cell and register it in the routing table through code.
- Each cell is an independent stack (EKS, router, drainer, scheduler, MemoryDB, Aurora) sized for about 360 TPS; deployment proceeds cell by cell.
