mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.150.0.0/16" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/pay-dev-euc1-cell-copy-automation" }
  }
}

variables {
  name_prefix  = "pay"
  environment  = "dev"
  region       = "eu-central-1"
  region_short = "euc1"
  account_id   = "111111111111"
  vpc_id       = "vpc-0abc"
  subnet_ids   = ["subnet-a", "subnet-b", "subnet-c"]
  cells = {
    cell-0 = { proxy_endpoint = "p0.proxy.example", proxy_security_group_id = "sg-p0", login_secret_arn = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:p0-AbCdEf" }
    cell-1 = { proxy_endpoint = "p1.proxy.example", proxy_security_group_id = "sg-p1", login_secret_arn = "arn:aws:secretsmanager:eu-central-1:111111111111:secret:p1-AbCdEf" }
  }
  secrets_kms_key_arns     = ["arn:aws:kms:eu-central-1:111111111111:key/cell-0", "arn:aws:kms:eu-central-1:111111111111:key/cell-1"]
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/workload-boundary"
  image_uri                = "111111111111.dkr.ecr.eu-central-1.amazonaws.com/payments/cell-copy@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  tags = {
    team = "payments-core", owner = "payments@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "none"
  }
}

run "documents_match_the_migration_script" {
  command = apply

  assert {
    condition     = toset(output.document_names) == toset(["cell-copy-merchant", "cell-verify-merchant"])
    error_message = "the script starts cell-copy-merchant and cell-verify-merchant"
  }
  assert {
    condition = alltrue([for d in aws_ssm_document.this : toset(keys(yamldecode(d.content).parameters)) == toset(["Merchant", "SourceCell", "TargetCell", "AutomationAssumeRole"]) &&
    yamldecode(d.content).parameters.AutomationAssumeRole.default == "arn:aws:iam::111111111111:role/pay-dev-euc1-cell-copy-automation"])
    error_message = "parameters of the script, and a default execution role because the script passes none"
  }
  assert {
    condition     = jsondecode(yamldecode(aws_ssm_document.this["cell-copy-merchant"].content).mainSteps[1].inputs.Payload).action == "copy"
    error_message = "the copy document invokes the copy action"
  }
}

run "function_reaches_only_the_cell_proxies" {
  command = plan

  assert {
    condition     = toset([for r in aws_vpc_security_group_egress_rule.to_proxy : r.referenced_security_group_id]) == toset(["sg-p0", "sg-p1"]) && aws_lambda_function.copy[0].reserved_concurrent_executions == 1
    error_message = "PostgreSQL to the cell proxies, one run at a time"
  }
}

run "image_must_be_pinned" {
  command = plan

  variables {
    image_uri = "111111111111.dkr.ecr.eu-central-1.amazonaws.com/payments/cell-copy:latest"
  }

  expect_failures = [var.image_uri]
}

run "copy_function_egress_stays_inside_the_vpc" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_egress_rule.https.cidr_ipv4 == "10.150.0.0/16"
    error_message = "the function reaches Secrets Manager through the VPC endpoint only, never the internet"
  }
}
