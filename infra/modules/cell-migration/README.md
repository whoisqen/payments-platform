# cell-migration

SSM Automation documents `cell-copy-merchant` and `cell-verify-merchant` that `scripts/cells/migrate-merchant.py` starts with `Merchant`, `SourceCell` and `TargetCell`
(no `AutomationAssumeRole`: the default is the module's automation role). Steps: reject equal cells, invoke `<prefix>-<env>-<region-short>-cell-copy`
with `{action: copy|verify, merchant, source, target}`, fail unless the function answers `{"ok": true}`. Copy upserts, so `copy` and `copy-delta` reuse it.
The function (container image by digest, arm64, one concurrent run, VPC) reads the hs_app logins of the cells and reaches only their RDS proxies on 5432.
Test: `terraform init -backend=false && terraform test`.
