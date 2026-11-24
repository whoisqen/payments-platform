mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::222222222222:role/pay-shared-services-euc1-central-external-secrets"
    }
  }
}
mock_provider "random" {}

variables {
  name_prefix              = "pay"
  region                   = "eu-central-1"
  account_id               = "222222222222"
  cluster_name             = "pay-shared-services-euc1-central"
  cluster_arn              = "arn:aws:eks:eu-central-1:222222222222:cluster/pay-shared-services-euc1-central"
  permissions_boundary_arn = "arn:aws:iam::222222222222:policy/workload-boundary"
  kms_key_arn              = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "secret_names_match_what_deploy_reads" {
  command = plan

  assert {
    condition = toset([for s in aws_secretsmanager_secret.this : s.name]) == toset([
      "pay/shared-services/alertmanager/deadmans-switch-url",
      "pay/shared-services/alertmanager/fallback-webhook-url",
      "pay/shared-services/alertmanager/slack-payments-alerts",
      "pay/shared-services/alertmanager/slack-payments-critical",
      "pay/shared-services/alertmanager/slack-security",
      "pay/shared-services/grafana/admin",
      "pay/shared-services/grafana/database",
      "pay/shared-services/otel-collector/tls",
      "pay/shared-services/sentry/admin-password",
      "pay/shared-services/sentry/clickhouse-password",
      "pay/shared-services/sentry/launchpad-rpc-secret",
      "pay/shared-services/sentry/postgres-password",
      "pay/shared-services/sentry/postgres-replication-password",
      "pay/shared-services/sentry/redis-password",
      "pay/shared-services/sentry/system-secret-key",
    ])
    error_message = "the 15 secret names must equal the keys of the ExternalSecrets in deploy/"
  }

  assert {
    condition     = alltrue([for s in aws_secretsmanager_secret.this : s.kms_key_id == var.kms_key_arn])
    error_message = "every secret is encrypted with the given key"
  }
}

run "no_values_unless_generated" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret_version.generated) == 0 && length(random_password.this) == 0
    error_message = "by default no secret has a version, so no value reaches the state"
  }
}

run "role_reads_only_the_prefix_and_decrypts_only_through_secrets_manager" {
  command = plan

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.external_secrets.policy).Statement : s.Resource if s.Sid == "ReadSecretsOfTheEnvironment"][0] == [
      "arn:aws:secretsmanager:eu-central-1:222222222222:secret:pay/shared-services/*"
    ]
    error_message = "secret read is limited to the <prefix>/<environment>/* ARN pattern"
  }

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.external_secrets.policy).Statement : s.Action if s.Sid == "ReadSecretsOfTheEnvironment"][0] == [
      "secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"
    ]
    error_message = "only read actions on secrets"
  }

  assert {
    condition = alltrue([for s in jsondecode(aws_iam_role_policy.external_secrets.policy).Statement :
      s.Resource == ["arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"] && s.Condition.StringEquals["kms:ViaService"] == "secretsmanager.eu-central-1.amazonaws.com"
      if s.Sid == "DecryptThroughSecretsManager"
    ])
    error_message = "kms:Decrypt on the given key only, only through Secrets Manager"
  }

  assert {
    condition = alltrue([for s in jsondecode(aws_iam_role_policy.external_secrets.policy).Statement :
      !contains(s.Resource, "*") if length([for a in s.Action : a if startswith(a, "kms:")]) > 0
    ])
    error_message = "no wildcard resource on any kms statement"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.external_secrets.policy).Statement : s.Effect == "Deny" || length([for a in s.Action : a if !contains(["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "kms:Decrypt"], a)]) == 0])
    error_message = "the allow statements hold read actions only"
  }

  assert {
    condition = alltrue([for a in ["secretsmanager:PutSecretValue", "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:UpdateSecret"] :
      contains([for s in jsondecode(aws_iam_role_policy.external_secrets.policy).Statement : s.Action if s.Sid == "NeverWriteSecrets"][0], a)
    ])
    error_message = "write actions are denied explicitly"
  }
}

run "role_is_bounded_and_bound_to_the_service_account" {
  command = plan

  assert {
    condition     = aws_iam_role.external_secrets.permissions_boundary == "arn:aws:iam::222222222222:policy/workload-boundary"
    error_message = "the permissions boundary is attached"
  }

  assert {
    condition     = aws_eks_pod_identity_association.external_secrets.namespace == "external-secrets" && aws_eks_pod_identity_association.external_secrets.service_account == "external-secrets" && aws_eks_pod_identity_association.external_secrets.cluster_name == "pay-shared-services-euc1-central"
    error_message = "the association is on external-secrets/external-secrets in the central cluster"
  }
}

run "generated_secrets_get_a_version_that_ignores_later_changes" {
  command = apply

  variables {
    generated_secrets = ["sentry/redis-password", "grafana/admin"]
  }

  assert {
    condition     = toset(keys(aws_secretsmanager_secret_version.generated)) == toset(["sentry/redis-password", "grafana/admin"])
    error_message = "only the listed secrets get a version"
  }
}

run "webhook_urls_cannot_be_generated" {
  command = plan

  variables {
    generated_secrets = ["alertmanager/slack-security"]
  }

  expect_failures = [var.generated_secrets]
}
