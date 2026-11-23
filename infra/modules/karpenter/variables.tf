variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-west-1."
  }
}

variable "account_id" {
  type        = string
  description = "AWS account of the cluster; builds role and instance profile ARNs without a data source."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the cluster from the eks module; the node and controller roles are named after it."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy of policy/iam/boundaries attached to the controller and node roles."
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "Customer managed key of the node volumes (pay-<env>-<region-short>-ebs-nodes)."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private app subnets of the three AZs; selected by id, so no discovery tags are needed."
  validation {
    condition     = length(var.subnet_ids) == 3
    error_message = "subnet_ids must list one subnet in each of three AZs."
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups of the nodes (node_security_group_id of the eks module)."
  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "at least one security group is required."
  }
}

variable "bottlerocket_version" {
  type        = string
  description = "Pinned Bottlerocket release, for example v1.49.0; latest is rejected so that a node image changes only through a pull request."
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.bottlerocket_version))
    error_message = "bottlerocket_version must look like v1.49.0."
  }
}

variable "max_pods" {
  type        = number
  default     = 110
  description = "Kubelet pod limit per node; prefix delegation of vpc-cni allows it."
}

variable "instance_families" {
  type        = map(list(string))
  description = "Instance families per pool; several families and both architectures keep the switch possible when one family has no capacity (plan B of D7)."
  default = {
    payments = ["m7g", "m6g", "m7i", "m6i"]
    stateful = ["r7g", "r6g", "r7i", "r6i"]
    cde      = ["m7g", "m6g", "m7i", "m6i"]
    workers  = ["m6g", "m7g", "m8g", "c7g", "c8g", "r7g", "m7i", "c7i"]
    # Graviton runners with local NVMe for builds, general purpose Graviton for tests and lint; x86 only builds the amd64 image.
    ci-build       = ["c7gd", "m7gd", "c6gd"]
    ci-build-amd64 = ["c7id", "m7id", "c6id"]
    ci-test        = ["m7g", "m6g", "c7g"]
    ci-light       = ["m7g", "m6g", "c7g"]
    ci-pr          = ["c7g", "m7g", "c6g", "m6g"]
  }
}

variable "cpu_limits" {
  type        = map(number)
  description = "CPU limit per pool; it caps the cost of a runaway scale-up."
  default = {
    payments       = 400
    stateful       = 100
    cde            = 200
    workers        = 400
    ci-build       = 128
    ci-build-amd64 = 32
    ci-test        = 64
    ci-light       = 48
    ci-pr          = 128
  }
}

variable "enabled_pools" {
  type        = list(string)
  description = "NodePools rendered for this cluster. Payments clusters keep the default; the shared-services cluster sets the ci-* pools so that CI pods never land on payments nodes and payment pools never exist next to runners."
  default     = ["payments", "stateful", "cde", "workers"]
  validation {
    condition     = length(var.enabled_pools) > 0 && alltrue([for n in var.enabled_pools : contains(["payments", "stateful", "cde", "workers", "ci-build", "ci-build-amd64", "ci-test", "ci-light", "ci-pr"], n)])
    error_message = "enabled_pools may contain payments, stateful, cde, workers, ci-build, ci-build-amd64, ci-test, ci-light and ci-pr only."
  }
  validation {
    condition     = !(anytrue([for n in var.enabled_pools : startswith(n, "ci-")]) && anytrue([for n in var.enabled_pools : !startswith(n, "ci-")]))
    error_message = "ci pools and payments pools must not share a cluster."
  }
}

variable "pull_through_cache_prefixes" {
  type        = list(string)
  default     = []
  description = "ECR pull-through cache repository prefixes that nodes may import into on a first pull; empty grants nothing."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."
  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}

variable "extra_node_tags" {
  type        = map(string)
  default     = {}
  description = "Remaining section 22 tags (environment, cell, component, managed-by, repo); Karpenter nodes and volumes get them from the EC2NodeClass, not from provider default_tags."
}
