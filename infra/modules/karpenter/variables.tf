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
  description = "Pinned Bottlerocket release, for example v1.70.0; latest is rejected so that a node image changes only through a pull request."
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.bottlerocket_version))
    error_message = "bottlerocket_version must look like v1.70.0."
  }
}

variable "max_pods" {
  type        = number
  default     = 110
  description = "Kubelet pod limit per node; prefix delegation of vpc-cni allows it."
}

variable "instance_families" {
  type        = map(list(string))
  description = "Instance families per pool; several families and both architectures keep capacity in us-east-1 when one family runs short."
  default = {
    payments = ["m7g", "m6g", "m7i", "m6i"]
    stateful = ["r7g", "r6g", "r7i", "r6i"]
    cde      = ["m7g", "m6g", "m7i", "m6i"]
    workers  = ["m6g", "m7g", "m8g", "c7g", "c8g", "r7g", "m7i", "c7i"]
    ci-build = ["c7gd", "c6gd", "m7gd", "c7g", "c8g"]
  }
}

variable "cpu_limits" {
  type        = map(number)
  description = "CPU limit per pool; it caps the cost of a runaway scale-up."
  default = {
    payments = 400
    stateful = 100
    cde      = 200
    workers  = 400
    ci-build = 64
  }
}

variable "enabled_pools" {
  type        = list(string)
  description = "NodePools rendered for this cluster; a cluster that holds no CDE workload may leave the cde pool out."
  default     = ["payments", "stateful", "cde", "workers"]
  validation {
    condition     = length(var.enabled_pools) > 0 && alltrue([for n in var.enabled_pools : contains(["payments", "stateful", "cde", "workers", "ci-build"], n)])
    error_message = "enabled_pools may contain payments, stateful, cde, workers and ci-build only."
  }
}

variable "workers_spot" {
  type        = bool
  default     = true
  description = "Whether the workers pool may use Spot; false for the locker and edge clusters, where every node is in the CDE."
}

variable "spot_pools" {
  type        = list(string)
  default     = []
  description = "Pools that may use Spot nodes besides the on-demand fallback; production lists none. Never the cde pool."
  validation {
    condition     = alltrue([for n in var.spot_pools : contains(["payments", "stateful", "workers"], n)])
    error_message = "spot_pools may contain payments, stateful and workers only: CDE nodes are never Spot."
  }
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

variable "container_log_max_size" {
  type        = string
  default     = "50Mi"
  description = "Size at which kubelet rotates a container log (Bottlerocket settings.kubernetes.container-log-max-size)."

  validation {
    condition     = can(regex("^[0-9]+(Ki|Mi|Gi)$", var.container_log_max_size))
    error_message = "container_log_max_size must look like 50Mi."
  }
}

variable "container_log_max_files" {
  type        = number
  default     = 5
  description = "Rotated container log files kubelet keeps per container (settings.kubernetes.container-log-max-files)."

  validation {
    condition     = var.container_log_max_files >= 2
    error_message = "container_log_max_files must be at least 2."
  }
}
