mock_provider "aws" {}

variables {
  name_prefix                = "pay"
  environment                = "prod"
  shared_services_account_id = "222222222222"
  permissions_boundary_arn   = "arn:aws:iam::444444444444:policy/workload-boundary"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "only_the_ci_roles_of_the_root_assume_it" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "pay-prod-tf-exec" && aws_iam_role.this.permissions_boundary == var.permissions_boundary_arn
    error_message = "name and boundary"
  }
  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.ArnLike["aws:PrincipalArn"] == [
      "arn:aws:iam::222222222222:role/pay-prod-glob-tf-plan", "arn:aws:iam::222222222222:role/pay-prod-glob-tf-apply-*",
    ]
    error_message = "plan and component apply roles of prod only"
  }
}
