mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-central-1:111111111111:key/11111111-1111-1111-1111-111111111111"
      key_id = "11111111-1111-1111-1111-111111111111"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/mock"
    }
  }
}

variables {
  name_prefix              = "pay"
  env                      = "stage"
  region                   = "eu-central-1"
  region_short             = "euc1"
  account_id               = "111111111111"
  cluster_name             = "pay-stage-euc1-cell-0-eks"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/workload-boundary"
  snapshot_bucket_arn      = "arn:aws:s3:::pay-stage-euc1-vault-snapshots"
  snapshot_kms_key_arn     = "arn:aws:kms:eu-central-1:111111111111:key/mrk-shared"
  secrets_kms_key_arn      = "arn:aws:kms:eu-central-1:111111111111:key/mrk-secrets"

  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "internal"
    "backup-tier" = "silver"
  }
}

run "names_and_associations" {
  command = apply

  assert {
    condition     = output.kms_key_alias == "alias/pay-stage-euc1-vault-unseal"
    error_message = "unseal alias alias/<prefix>-<env>-<region-short>-vault-unseal"
  }

  assert {
    condition     = aws_iam_role.this["server"].name == "pay-stage-euc1-vault-server" && aws_iam_role.this["snapshot"].name == "pay-stage-euc1-vault-snapshot" && aws_iam_role.this["bootstrap"].name == "pay-stage-euc1-vault-bootstrap"
    error_message = "role names vault-server, vault-snapshot, vault-bootstrap"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["server"].service_account == "vault" && aws_eks_pod_identity_association.this["snapshot"].service_account == "vault-snapshot" && aws_eks_pod_identity_association.this["bootstrap"].service_account == "vault-bootstrap" && alltrue([for a in aws_eks_pod_identity_association.this : a.namespace == "vault" && a.cluster_name == "pay-stage-euc1-cell-0-eks"])
    error_message = "one association per role: vault/vault, vault/vault-snapshot, vault/vault-bootstrap on the cell cluster"
  }
}

run "roles_trust_pod_identity_with_boundary" {
  command = apply

  assert {
    condition     = alltrue([for r in aws_iam_role.this : r.permissions_boundary == "arn:aws:iam::111111111111:policy/workload-boundary" && strcontains(r.assume_role_policy, "pods.eks.amazonaws.com") && strcontains(r.assume_role_policy, "sts:TagSession")])
    error_message = "Pod Identity trust and permissions boundary on every role"
  }
}

run "server_policy_only_seal_actions" {
  command = apply

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.server.policy).Statement[0].Action) == toset(["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]) && length(jsondecode(aws_iam_role_policy.server.policy).Statement) == 1
    error_message = "server may only Encrypt, Decrypt and DescribeKey"
  }
}

run "snapshot_policy_scoped_to_raft_prefix" {
  command = apply

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.snapshot.policy).Statement[0].Action) == toset(["s3:PutObject", "s3:AbortMultipartUpload"]) && jsondecode(aws_iam_role_policy.snapshot.policy).Statement[0].Resource == ["arn:aws:s3:::pay-stage-euc1-vault-snapshots/raft/*"]
    error_message = "writes only under raft/"
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.snapshot.policy).Statement[1].Action) == toset(["s3:ListBucket", "s3:GetBucketLocation"]) && jsondecode(aws_iam_role_policy.snapshot.policy).Statement[1].Resource == ["arn:aws:s3:::pay-stage-euc1-vault-snapshots"]
    error_message = "list and location on the bucket"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.snapshot.policy).Statement[2].Resource == ["arn:aws:kms:eu-central-1:111111111111:key/mrk-shared"]
    error_message = "bucket key only"
  }
}

run "bootstrap_policy_scoped_to_vault_secrets" {
  command = apply

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.bootstrap.policy).Statement[0].Action) == toset(["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue", "secretsmanager:DescribeSecret"]) && jsondecode(aws_iam_role_policy.bootstrap.policy).Statement[0].Resource == ["arn:aws:secretsmanager:eu-central-1:111111111111:secret:pay/stage/vault/*"]
    error_message = "secrets limited to pay/stage/vault/*"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.bootstrap.policy).Statement[1].Resource == ["arn:aws:kms:eu-central-1:111111111111:key/mrk-secrets"]
    error_message = "secrets key only"
  }
}

run "no_wildcard_actions_or_resources" {
  command = apply

  assert {
    condition = alltrue([
      for p in [aws_iam_role_policy.server.policy, aws_iam_role_policy.snapshot.policy, aws_iam_role_policy.bootstrap.policy] :
      alltrue([for s in jsondecode(p).Statement : alltrue([for a in s.Action : !strcontains(a, "*")]) && !contains(s.Resource, "*")])
    ])
    error_message = "no * actions and no bare * resources"
  }
}

run "tags_are_required" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}
