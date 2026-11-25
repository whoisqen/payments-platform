# fis

AWS FIS experiment templates for the stage account only; `${STAGE_ACCOUNT_ID}` is substituted by the runner, never a prod or CDE account.
Each template has `Hypothesis:` in its description, the `chaos-stop` alarm as stop condition and a `failure-mode` tag (see `docs/chaos/catalog.md`).
MemoryDB failover and MSK broker loss go through SSM Automation documents because FIS has no native action for them; targets select on the default tags of `infra/live/terragrunt.hcl` and pick an AZ with an attribute filter, as in `infra/modules/fis-experiments`.
Checked offline by `../lib/validate_fis.py`; creating or starting an experiment is a pipeline job, not done from here.
