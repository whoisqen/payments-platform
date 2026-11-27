mock_provider "aws" {}

variables {
  account_id = "111111111111"
  tags = {
    team = "security", owner = "security@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "boundary_name_matches_env_hcl" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.name == "workload-boundary"
    error_message = "env.hcl builds arn:aws:iam::<account>:policy/workload-boundary"
  }
}

run "new_roles_must_carry_the_boundary" {
  command = plan

  assert {
    condition = anytrue([for s in jsondecode(aws_iam_policy.this.policy).Statement :
    s.Effect == "Deny" && contains(s.Action, "iam:CreateRole") && s.Condition.StringNotEquals["iam:PermissionsBoundary"] == "arn:aws:iam::111111111111:policy/workload-boundary"])
    error_message = "CreateRole without the boundary is denied"
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Effect == "Deny" || contains(s.NotAction, "iam:CreateAccessKey")])
    error_message = "the ceiling excludes long-term credentials"
  }
}
