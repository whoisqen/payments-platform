# live

Terragrunt stacks: `<env>/<region>[/<cell>]/<component>/terragrunt.hcl`; environment, region, cell and component come from the path, the account from `<env>/env.hcl`.
`terragrunt.hcl` holds the S3 state (`use_lockfile`, KMS, `<env>/` prefix), the generated provider with `default_tags` of section 22 and the shared inputs.
`_envcommon/<group>/<component>.hcl` holds the module source and the settings every stack of a component shares.
eu-central-1 is the only writing region (cells `cell-0` to `cell-3` and `spare`, each with its own cluster and data stores, plus the shared locker Aurora).
us-east-1 and us-east-2 hold only non-compute resources: VPC, KMS replica keys, ECR replicas and headless Aurora secondaries; DynamoDB, S3 and secrets replicas and backup vaults are owned by the eu-central-1 stacks.
First apply of an environment: `tgw`, then set `transit_gateway_id` in `env.hcl` so that `vpc` routes through it.
`prod` and `cde-prod` are written separately.
