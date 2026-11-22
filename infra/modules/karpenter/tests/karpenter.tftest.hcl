mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-central-1:111111111111:pay-dev-euc1-eks-cell-0"
    }
  }
}

variables {
  region                   = "eu-central-1"
  account_id               = "111111111111"
  cluster_name             = "pay-dev-euc1-eks-cell-0"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/workload-boundary"
  ebs_kms_key_arn          = "arn:aws:kms:eu-central-1:111111111111:key/cccc"
  subnet_ids               = ["subnet-a", "subnet-b", "subnet-c"]
  security_group_ids       = ["sg-0node"]
  bottlerocket_version     = "v1.49.0"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "none"
  }
}

run "nodeclass_is_hardened" {
  command = plan

  assert {
    condition     = yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.metadataOptions.httpTokens == "required" && yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.metadataOptions.httpPutResponseHopLimit == 1
    error_message = "IMDSv2 with hop limit 1"
  }
  assert {
    condition     = alltrue([for b in yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.blockDeviceMappings : b.ebs.encrypted && b.ebs.volumeType == "gp3" && b.ebs.kmsKeyID == var.ebs_kms_key_arn])
    error_message = "volumes are encrypted gp3 with the nodes key"
  }
  assert {
    condition     = yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.associatePublicIPAddress == false
    error_message = "nodes have no public IP"
  }
  assert {
    condition     = yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.amiSelectorTerms[0].alias == "bottlerocket@v1.49.0"
    error_message = "the image is a pinned Bottlerocket release"
  }
  assert {
    condition     = yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.role == "pay-dev-euc1-eks-cell-0-node"
    error_message = "the node role is the minimal role of this module"
  }
  assert {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(yamldecode(output.manifests["ec2nodeclass-hardened.yaml"]).spec.tags), k)])
    error_message = "nodes and volumes carry the required tags"
  }
}

run "payment_pools_never_use_spot_and_are_tainted" {
  command = plan

  assert {
    condition     = alltrue([for n in ["payments", "stateful", "cde"] : !contains(flatten([for r in { for k, v in output.manifests : trimprefix(trimsuffix(k, ".yaml"), "nodepool-") => yamldecode(v) if startswith(k, "nodepool-") }[n].spec.template.spec.requirements : r.values if r.key == "karpenter.sh/capacity-type"]), "spot")])
    error_message = "payments, stateful and cde must not allow Spot"
  }
  assert {
    condition     = alltrue([for n, p in { for k, v in output.manifests : trimprefix(trimsuffix(k, ".yaml"), "nodepool-") => yamldecode(v) if startswith(k, "nodepool-") } : length(p.spec.template.spec.taints) == 1 && p.spec.template.spec.taints[0].key == "workload" && p.spec.template.spec.taints[0].effect == "NoSchedule"])
    error_message = "every pool has a workload taint"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-cde.yaml"]).spec.template.spec.taints[0].value == "cde" && yamldecode(output.manifests["nodepool-stateful.yaml"]).spec.template.spec.taints[0].value == "stateful"
    error_message = "taint values follow the pool"
  }
  assert {
    condition     = alltrue([for n, p in { for k, v in output.manifests : trimprefix(trimsuffix(k, ".yaml"), "nodepool-") => yamldecode(v) if startswith(k, "nodepool-") } : p.spec.template.spec.expireAfter != null && p.spec.template.spec.terminationGracePeriod != null])
    error_message = "every pool rotates nodes and bounds the drain time"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-payments.yaml"]).spec.template.spec.terminationGracePeriod == "30m"
    error_message = "payment nodes give PSP calls 30 minutes to finish"
  }
}

run "plan_b_families_and_architectures" {
  command = plan

  assert {
    condition     = alltrue([for n, p in { for k, v in output.manifests : trimprefix(trimsuffix(k, ".yaml"), "nodepool-") => yamldecode(v) if startswith(k, "nodepool-") } : length(flatten([for r in p.spec.template.spec.requirements : r.values if r.key == "karpenter.k8s.aws/instance-family"])) >= 4])
    error_message = "each pool allows at least four families"
  }
  assert {
    condition     = alltrue([for n, p in { for k, v in output.manifests : trimprefix(trimsuffix(k, ".yaml"), "nodepool-") => yamldecode(v) if startswith(k, "nodepool-") } : contains(flatten([for r in p.spec.template.spec.requirements : r.values if r.key == "kubernetes.io/arch"]), "amd64")])
    error_message = "amd64 stays allowed for plan B"
  }
}

run "latest_image_is_rejected" {
  command = plan

  variables {
    bottlerocket_version = "latest"
  }

  expect_failures = [var.bottlerocket_version]
}

run "node_role_is_minimal_and_has_a_boundary" {
  command = plan

  assert {
    condition     = aws_iam_role.node.permissions_boundary == var.permissions_boundary_arn && aws_iam_role.controller.permissions_boundary == var.permissions_boundary_arn
    error_message = "both roles carry the boundary"
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.node) == 3 && aws_eks_access_entry.node.type == "EC2_LINUX"
    error_message = "node role has three managed policies and an EC2_LINUX entry"
  }
}

run "interruption_queue_listens_to_four_events" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.interruption) == 4
    error_message = "four interruption event rules"
  }
}

run "cpu_limits_follow_the_override" {
  command = plan

  variables {
    cpu_limits = { payments = 32, stateful = 16, cde = 16, workers = 32, ci = 8, ci-prod = 4 }
  }

  assert {
    condition     = yamldecode(output.manifests["nodepool-payments.yaml"]).spec.limits.cpu == "32" && yamldecode(output.manifests["nodepool-stateful.yaml"]).spec.limits.cpu == "16"
    error_message = "pool CPU limits must come from cpu_limits"
  }
}

run "payments_cluster_has_no_ci_pools" {
  command = plan

  assert {
    condition     = !contains(keys(output.manifests), "nodepool-ci.yaml") && !contains(keys(output.manifests), "nodepool-ci-prod.yaml") && contains(keys(output.manifests), "nodepool-payments.yaml")
    error_message = "ci pools are rendered only when enabled"
  }
}

run "ci_pools_in_shared_services" {
  command = plan

  variables {
    enabled_pools = ["ci", "ci-prod", "ci-pr"]
  }

  assert {
    condition     = length([for k in keys(output.manifests) : k if startswith(k, "nodepool-")]) == 3 && !contains(keys(output.manifests), "nodepool-payments.yaml")
    error_message = "only the ci pools are rendered"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-ci-pr.yaml"]).spec.template.spec.taints[0].value == "ci-pr" && yamldecode(output.manifests["nodepool-ci-pr.yaml"]).spec.limits.cpu == "100"
    error_message = "ci-pr has its own tainted pool"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-ci.yaml"]).spec.template.spec.taints[0].value == "ci" && yamldecode(output.manifests["nodepool-ci-prod.yaml"]).spec.template.spec.taints[0].value == "ci-prod"
    error_message = "taints workload=ci and workload=ci-prod, NoSchedule"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-ci-prod.yaml"]).spec.template.spec.requirements[2].values == ["on-demand"] && contains(yamldecode(output.manifests["nodepool-ci.yaml"]).spec.template.spec.requirements[2].values, "spot")
    error_message = "ci-prod is On-Demand, ci may use Spot"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-ci.yaml"]).spec.limits.cpu == "200" && yamldecode(output.manifests["nodepool-ci-prod.yaml"]).spec.limits.cpu == "100"
    error_message = "default ci limits"
  }
  assert {
    condition     = yamldecode(output.manifests["nodepool-ci.yaml"]).spec.template.metadata.labels["platform.io/pci-scope"] == "none"
    error_message = "ci nodes are outside the CDE"
  }
}

run "ci_and_payments_pools_cannot_mix" {
  command = plan

  variables {
    enabled_pools = ["payments", "ci"]
  }

  expect_failures = [var.enabled_pools]
}
