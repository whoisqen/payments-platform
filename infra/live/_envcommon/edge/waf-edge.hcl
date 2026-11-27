locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  waf     = try(local.env_cfg.cfg.waf, {})
}

terraform {
  source = "${get_repo_root()}/infra/modules//waf-edge"
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "logs" = "arn:aws:kms:us-east-1:000000000000:key/mrk-logs"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# CLOUDFRONT scope exists only in us-east-1; every unit sits under <env>/us-east-1.
inputs = {
  scope = "CLOUDFRONT"
  # Managed groups block in stage and prod; a rule that misfires stays in count through waf.count_overrides of config/platform.yaml.
  mode               = try(local.waf.mode[local.env_cfg.environment], local.env_cfg.environment == "dev" ? "count" : "block")
  count_overrides    = try(local.waf.count_overrides, {})
  rate_limit_ip      = try(local.waf.rate_limit_ip, 2000)
  rate_limit_api_key = try(local.waf.rate_limit_api_key, 1000)
  rate_limit_auth    = try(local.waf.rate_limit_auth, 100)
  entries = {
    panel = {
      bot_control = true
      atp         = true
      login_path  = try(local.waf.login_path, "/login")
      auth_paths  = try(local.waf.auth_paths, ["/login", "/auth/"])
    }
    sdk = {}
  }
  kms_key_arn = dependency.kms.outputs.key_arns["logs"]
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "public"
    backup-tier = "none"
  }
}
