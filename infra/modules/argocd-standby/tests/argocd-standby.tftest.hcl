mock_provider "aws" {}

override_resource {
  target          = aws_iam_role.controller
  override_during = plan
  values          = { arn = "arn:aws:iam::444444444444:role/pay-prod-use1-argocd-standby" }
}

variables {
  name_prefix = "pay"
  environment = "prod"
  region      = "us-east-1"
  host_cluster = {
    name              = "pay-prod-use1-eks-cell-0"
    oidc_provider_arn = "arn:aws:iam::444444444444:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/ABC"
    oidc_issuer       = "oidc.eks.us-east-1.amazonaws.com/id/ABC"
  }
  clusters                 = { cell-0 = "pay-prod-use1-eks-cell-0", cell-1 = "pay-prod-use1-eks-cell-1" }
  managed_namespaces       = ["router", "locker"]
  permissions_boundary_arn = "arn:aws:iam::444444444444:policy/workload-boundary"
  tags                     = { team = "platform", owner = "platform@example.com", pci-scope = "cde", data-class = "internal", backup-tier = "none" }
}

run "controller_reaches_every_cluster_namespaced" {
  command = plan

  assert {
    condition     = aws_iam_role.controller.name == "pay-prod-use1-argocd-standby" && aws_iam_role.controller.permissions_boundary == var.permissions_boundary_arn
    error_message = "role name and boundary"
  }
  assert {
    condition     = jsondecode(aws_iam_role.controller.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/ABC:sub"] == ["system:serviceaccount:argocd:argocd-application-controller"]
    error_message = "only the application controller of the host cluster"
  }
  assert {
    condition     = toset(keys(aws_eks_access_policy_association.controller)) == toset(["cell-0", "cell-1"])
    error_message = "one entry per standby cluster"
  }
  assert {
    condition     = alltrue([for a in aws_eks_access_policy_association.controller : a.access_scope[0].type == "namespace" && endswith(a.policy_arn, "/AmazonEKSAdminPolicy")])
    error_message = "namespaced admin, never cluster-admin"
  }
}

run "no_installer_by_default" {
  command = plan

  assert {
    condition     = length(aws_eks_access_entry.installer) == 0
    error_message = "cluster-admin only while installing"
  }
}

run "installer_is_cluster_admin_on_the_host_only" {
  command = plan

  variables {
    installer_role_arn = "arn:aws:iam::444444444444:role/pay-prod-glob-dr-apply"
  }

  assert {
    condition     = aws_eks_access_entry.installer[0].cluster_name == "pay-prod-use1-eks-cell-0" && aws_eks_access_policy_association.installer[0].access_scope[0].type == "cluster"
    error_message = "installer on the host cluster"
  }
}

run "working_region_rejected" {
  command = plan

  variables {
    region = "eu-central-1"
  }

  expect_failures = [var.region]
}
