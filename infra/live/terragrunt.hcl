# Root of every live stack: path infra/live/<env>/<region>[/<cell>]/<component> gives environment, region, cell and component.
locals {
  parts        = split("/", path_relative_to_include("root"))
  env          = local.parts[0]
  region       = local.parts[1]
  component    = element(local.parts, length(local.parts) - 1)
  cell         = length(local.parts) == 4 ? local.parts[2] : "shared"
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1" }[local.region]

  # The account comes from env.hcl because the path carries no account segment.
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg

  # PAY_STATE_REGION picks the working bucket (default) or a recovery replica; an unknown value fails instead of naming a new bucket.
  state_region       = get_env("PAY_STATE_REGION", local.cfg.regions.working)
  state_region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1" }[local.state_region]
  # The replica of a multi-Region key keeps the key id, so only the region part of the ARN changes.
  state_kms_key_arn = replace(local.env_cfg.state_kms_key_arn, ":${local.cfg.regions.working}:", ":${local.state_region}:")
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  # Every stack keeps its state in the bucket of infra/bootstrap under its own <env>/ prefix; dependencies read the same bucket.
  config = {
    bucket       = "${local.cfg.naming.prefix}-${local.env}-${local.state_region_short}-tf-state-${local.env_cfg.shared_services_account_id}"
    key          = "${path_relative_to_include("root")}/terraform.tfstate"
    region       = local.state_region
    encrypt      = true
    use_lockfile = true
    kms_key_id   = local.state_kms_key_arn
  }
}

# Tags of section 22 that the path can fill; the other five come from required module variables.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region              = "${local.region}"
      allowed_account_ids = ["${local.env_cfg.account_id}"]

      default_tags {
        tags = {
          environment = "${local.env}"
          cell        = "${local.cell}"
          component   = "${local.component}"
          cost-center = "${local.env_cfg.cost_center}"
          managed-by  = "terraform"
          repo        = "infra/live/${path_relative_to_include("root")}"
        }
      }
    }
  EOT
}

# Names that a module does not declare are ignored by Terraform, so one set of inputs serves every module.
inputs = {
  environment    = local.env
  env            = local.env
  region         = local.region
  region_name    = local.region
  region_short   = local.region_short
  primary_region = local.cfg.regions.working
  name_prefix    = local.cfg.naming.prefix
  account_id     = local.env_cfg.account_id
}
