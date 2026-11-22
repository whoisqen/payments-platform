module "state_key" {
  source = "../modules/kms"

  account_id  = var.account_id
  region      = "eu-central-1"
  environment = var.environment
  component   = "tf-state"
  tags        = var.tags
}

module "state_key_use1" {
  source = "../modules/kms"

  providers = { aws = aws.use1 }

  account_id      = var.account_id
  region          = "us-east-1"
  environment     = var.environment
  component       = "tf-state"
  is_replica      = true
  primary_key_arn = module.state_key.key_arn
  tags            = var.tags
}

module "state_key_use2" {
  source = "../modules/kms"

  providers = { aws = aws.use2 }

  account_id      = var.account_id
  region          = "us-east-2"
  environment     = var.environment
  component       = "tf-state"
  is_replica      = true
  primary_key_arn = module.state_key.key_arn
  tags            = var.tags
}
