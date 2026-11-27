module "state_key" {
  source = "../modules/kms"

  account_id     = var.account_id
  region         = "eu-central-1"
  environment    = var.environment
  name_prefix    = var.name_prefix
  component      = "tf-state"
  user_role_arns = var.dr_apply_role_arns
  tags           = var.tags
}

module "state_key_use1" {
  source = "../modules/kms"

  providers = { aws = aws.use1 }

  account_id      = var.account_id
  region          = "us-east-1"
  environment     = var.environment
  name_prefix     = var.name_prefix
  component       = "tf-state"
  is_replica      = true
  primary_key_arn = module.state_key.key_arn
  user_role_arns  = var.dr_apply_role_arns
  tags            = var.tags
}

removed {
  from = module.state_key_use2

  lifecycle {
    destroy = false
  }
}
