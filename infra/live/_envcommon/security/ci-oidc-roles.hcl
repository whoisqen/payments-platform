locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg

  acct      = local.env_cfg.account_id
  recovery  = local.cfg.regions.recovery[0]
  rec_short = { "us-east-1" = "use1" }[local.recovery]
  # Only prod has a standby region; its switch role builds or repairs the us-east-1 compute units against the state replica.
  dr_apply = local.env_cfg.environment == "prod" ? {
    github_environment        = "dr-compute-${local.env_cfg.environment}"
    state_replica_bucket_arn  = "arn:aws:s3:::${local.cfg.naming.prefix}-${local.env_cfg.environment}-${local.rec_short}-tf-state-${local.env_cfg.shared_services_account_id}"
    state_replica_kms_key_arn = replace(local.env_cfg.state_kms_key_arn, ":${local.cfg.regions.working}:", ":${local.recovery}:")
    actions = [
      "eks:*", "memorydb:*", "sqs:*", "events:*", "logs:*",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules", "ec2:CreateTags", "ec2:DeleteTags",
      "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion", "ec2:DeleteLaunchTemplate", "ec2:ModifyLaunchTemplate", "ec2:RunInstances",
      "kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey",
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:PassRole", "iam:PutRolePermissionsBoundary",
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
    ]
    resource_arns = [
      "arn:aws:eks:${local.recovery}:${local.acct}:*",
      "arn:aws:memorydb:${local.recovery}:${local.acct}:*",
      "arn:aws:sqs:${local.recovery}:${local.acct}:*",
      "arn:aws:events:${local.recovery}:${local.acct}:rule/*",
      "arn:aws:logs:${local.recovery}:${local.acct}:log-group:*",
      "arn:aws:ec2:${local.recovery}:${local.acct}:*",
      "arn:aws:ec2:${local.recovery}::image/*",
      "arn:aws:kms:${local.recovery}:${local.acct}:key/*",
      "arn:aws:iam::${local.acct}:role/${local.cfg.naming.prefix}-${local.env_cfg.environment}-${local.rec_short}-*",
      "arn:aws:iam::${local.acct}:oidc-provider/oidc.eks.${local.recovery}.amazonaws.com/*",
    ]
    unscoped_actions = ["ec2:Describe*", "eks:DescribeAddonVersions", "memorydb:Describe*", "iam:CreateServiceLinkedRole", "sts:GetCallerIdentity"]
  } : null
}

terraform {
  source = "${get_repo_root()}/infra/modules//ci-oidc-roles"
}

# Plan only from the nightly drift check on main (vars.AWS_ROLE_TF_PLAN); pull requests get no state access; apply roles are added per component when the apply workflow exists.
inputs = {
  github_repository        = "${local.cfg.owner.github_org}/${local.cfg.owner.github_repo}"
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  state_bucket_arn         = "arn:aws:s3:::${local.cfg.naming.prefix}-${local.env_cfg.environment}-euc1-tf-state-${local.env_cfg.shared_services_account_id}"
  state_kms_key_arn        = local.env_cfg.state_kms_key_arn
  plan_refs                = ["refs/heads/main"]
  dr_apply                 = local.dr_apply
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
