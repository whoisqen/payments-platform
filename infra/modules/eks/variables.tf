variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region name such as eu-west-1."
  }
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "component" {
  type        = string
  description = "Cluster name segment, for example eks-cell-0 or eks-edge; the cluster is pay-<env>-<region-short>-<component>."
}

variable "kubernetes_version" {
  type        = string
  description = "Control plane version; node images and add-ons follow it."
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.34."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC of the cluster."
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR; node egress inside the VPC is limited to it."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private app subnets, one per AZ; the endpoint is private and no public subnet is used."
  validation {
    condition     = length(var.subnet_ids) == 3
    error_message = "subnet_ids must list one subnet in each of three AZs."
  }
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Customer managed key for Kubernetes Secrets envelope encryption."
}

variable "logs_kms_key_arn" {
  type        = string
  description = "Customer managed key of the control-plane log group; its policy must allow logs.amazonaws.com."
}

variable "ebs_kms_key_arn" {
  type        = string
  description = "Key of the node and volume encryption (pay-<env>-<region-short>-ebs-nodes)."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy of policy/iam/boundaries attached to every role of the cluster."
}

variable "log_retention_days" {
  type        = number
  default     = 365
  description = "Retention of control-plane logs; PCI DSS 10.5.1 keeps one year."
}

variable "access_entries" {
  type = map(object({
    principal_arn     = string
    policy_arn        = string
    scope             = optional(string, "cluster")
    namespaces        = optional(list(string), [])
    kubernetes_groups = optional(list(string), [])
  }))
  default     = {}
  description = "EKS access entries by name; people get view only, ArgoCD a namespaced scope, nobody cluster-admin."
  validation {
    condition     = alltrue([for e in var.access_entries : !endswith(e.policy_arn, "/AmazonEKSClusterAdminPolicy") && contains(["cluster", "namespace"], e.scope)])
    error_message = "cluster-admin is not allowed and scope must be cluster or namespace."
  }
}

variable "addon_versions" {
  type        = map(string)
  default     = {}
  description = "Pinned add-on versions by add-on name; an add-on without an entry takes the default version of the cluster version."
}

variable "bootstrap_instance_types" {
  type        = list(string)
  default     = ["m7g.large"]
  description = "Types of the small managed node group that hosts CoreDNS and Karpenter, which cannot start on nodes they provision."
}

variable "bootstrap_node_count" {
  type        = number
  default     = 3
  description = "Bootstrap nodes, at least one per AZ."
  validation {
    condition     = var.bootstrap_node_count >= 3
    error_message = "bootstrap_node_count must keep one node in each AZ."
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

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
