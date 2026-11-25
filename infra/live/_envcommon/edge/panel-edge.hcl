locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  edge    = try(local.cfg.panel_edge, {})
}

terraform {
  source = "${get_repo_root()}/infra/modules//panel-edge"
}

dependency "waf" {
  config_path = "../waf-edge"

  mock_outputs = {
    web_acl_arns = {
      panel = "arn:aws:wafv2:us-east-1:000000000000:global/webacl/mock-panel/00000000-0000-0000-0000-000000000000"
      sdk   = "arn:aws:wafv2:us-east-1:000000000000:global/webacl/mock-sdk/00000000-0000-0000-0000-000000000000"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
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

dependency "dns" {
  config_path = "../../${local.cfg.regions.working}/edge-dns"

  mock_outputs = {
    zone_id = "Z00000000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# CloudFront certificates and the logging v2 source exist only in us-east-1; every unit sits under <env>/us-east-1.
# Second step of the apply: set panel_edge.nlb_lookup_enabled.<env> once the panel Gateway has its NLB.
inputs = {
  zone_name          = local.env_cfg.zone_name
  zone_id            = dependency.dns.outputs.zone_id
  web_acl_arns       = dependency.waf.outputs.web_acl_arns
  kms_key_arn        = dependency.kms.outputs.key_arns["logs"]
  origin_region      = local.cfg.regions.working
  nlb_lookup_enabled = try(local.edge.nlb_lookup_enabled[local.env_cfg.environment], false)
  nlb_stack_tag      = try(local.edge.nlb_stack_tag, null)
  nlb_cluster_name   = try(local.edge.nlb_cluster_name[local.env_cfg.environment], null)
  log_bucket_arn     = try(local.edge.log_bucket_arn[local.env_cfg.environment], null)
  geo_restriction    = try(local.edge.geo_restriction, {})
  price_class        = try(local.edge.price_class, "PriceClass_100")
  entries = {
    panel = {
      subdomain       = try(local.edge.subdomains.panel, "panel")
      forward_cookies = try(local.edge.panel_cookies, [])
    }
    sdk = {
      subdomain               = try(local.edge.subdomains.sdk, "sdk")
      frame_deny              = false
      content_security_policy = "default-src 'self'; object-src 'none'; base-uri 'self'"
    }
  }
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "public"
    backup-tier = "none"
  }
}
