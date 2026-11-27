mock_provider "aws" {
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:eu-central-1:222222222222:secret:pay/argocd/clusters/pay-dev-euc1-locker-AbCdEf" }
  }
}

variables {
  name_prefix                = "pay"
  environment                = "dev"
  cluster_region             = "eu-central-1"
  argocd_cluster_name        = "pay-dev-euc1-locker"
  cluster_name               = "pay-dev-euc1-eks-locker"
  cluster_endpoint           = "https://ABC.gr7.eu-central-1.eks.amazonaws.com"
  certificate_authority_data = "Q0E="
  controller_role_arn        = "arn:aws:iam::111111111111:role/pay-dev-argocd-controller"
  reader_role_arn            = "arn:aws:iam::222222222222:role/pay-shared-services-euc1-central-external-secrets"
  writer_role_arn            = "arn:aws:iam::222222222222:role/pay-shared-services-argocd-registration"
  oidc_issuer                = "https://oidc.eks.eu-central-1.amazonaws.com/id/ABC"
  vault_bootstrap_role_arn   = "arn:aws:iam::222222222222:role/pay-shared-services-euc1-vault-bootstrap"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "secret_matches_the_contract" {
  command = apply

  assert {
    condition     = aws_secretsmanager_secret.this.name == "pay/argocd/clusters/pay-dev-euc1-locker"
    error_message = "secret name <prefix>/argocd/clusters/<argocd cluster name>"
  }
  assert {
    condition = jsondecode(aws_secretsmanager_secret_version.this.secret_string) == {
      name       = "pay-dev-euc1-locker", server = "https://ABC.gr7.eu-central-1.eks.amazonaws.com", caData = "Q0E=",
      roleARN    = "arn:aws:iam::111111111111:role/pay-dev-argocd-controller", clusterName = "pay-dev-euc1-eks-locker", environment = "dev", region = "eu-central-1",
      oidcIssuer = "https://oidc.eks.eu-central-1.amazonaws.com/id/ABC"
    }
    error_message = "registration JSON"
  }
}

run "only_external_secrets_reads" {
  command = apply

  assert {
    condition = anytrue([for s in jsondecode(aws_secretsmanager_secret_policy.this.policy).Statement :
      s.Effect == "Deny" && s.Principal == "*" && contains(s.Action, "secretsmanager:GetSecretValue") &&
    toset(s.Condition.ArnNotEquals["aws:PrincipalArn"]) == toset([var.reader_role_arn, var.writer_role_arn, var.vault_bootstrap_role_arn])])
    error_message = "everyone but the reader and the writer is denied"
  }
  assert {
    condition     = anytrue([for s in jsondecode(aws_secretsmanager_secret_policy.this.policy).Statement : s.Effect == "Allow" && s.Principal.AWS == var.reader_role_arn])
    error_message = "the External Secrets role is allowed"
  }
}

run "vault_reads_the_issuer_and_nobody_else_is_added" {
  command = plan

  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.this.secret_string).oidcIssuer == var.oidc_issuer
    error_message = "the registration names the OIDC issuer Vault verifies the cluster's tokens against"
  }
  assert {
    condition = toset(one([for st in jsondecode(aws_secretsmanager_secret_policy.this.policy).Statement : st.Condition.ArnNotEquals["aws:PrincipalArn"] if st.Sid == "NobodyElseReads"])) == toset([
      var.reader_role_arn, var.writer_role_arn, var.vault_bootstrap_role_arn,
    ])
    error_message = "only External Secrets, the writer and the Vault bootstrap read the registration"
  }
}
