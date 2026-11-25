variable "name_prefix" {
  type        = string
  description = "Naming prefix (pay)."
}

variable "environment" {
  type        = string
  description = "Environment of the account; chaos runs in stage, prod only with allow_prod."

  validation {
    condition     = contains(["stage", "prod"], var.environment)
    error_message = "environment must be stage or prod."
  }
}

variable "allow_prod" {
  type        = bool
  description = "Guard for prod: without it a prod stack creates the role and log group but no experiment template."
  default     = false
}

variable "region" {
  type        = string
  description = "Region of the experiments."
}

variable "region_short" {
  type        = string
  description = "Short region name used in resource names (euc1)."
}

variable "account_id" {
  type        = string
  description = "Account that runs the experiments; FIS targets only resources of this account."
}

variable "stop_alarm_arns" {
  type        = list(string)
  description = "CloudWatch alarms that stop every experiment (chaos-stop: burn rate 14.4 or authorization rate drop above 2 pp); they must exist before apply."

  validation {
    condition     = length(var.stop_alarm_arns) > 0 && length(var.stop_alarm_arns) <= 5 && alltrue([for a in var.stop_alarm_arns : startswith(a, "arn:aws:cloudwatch:")])
    error_message = "stop_alarm_arns needs one to five CloudWatch alarm ARNs."
  }
}

variable "target_cell" {
  type        = string
  description = "Cell whose resources the experiments target (tag cell)."
}

variable "target_az" {
  type        = string
  description = "Availability zone that loses nodes or connectivity; the blast radius is never more than one AZ."
}

variable "node_pool" {
  type        = string
  description = "Karpenter NodePool whose nodes the node-loss experiment terminates."
  default     = "payments"
}

variable "node_selection_mode" {
  type        = string
  description = "How many nodes of the pool in target_az are terminated: COUNT(n), PERCENT(n) or ALL."
  default     = "COUNT(1)"

  validation {
    condition     = can(regex("^(ALL|COUNT\\([0-9]+\\)|PERCENT\\([0-9]+\\))$", var.node_selection_mode))
    error_message = "node_selection_mode must be ALL, COUNT(n) or PERCENT(n)."
  }
}

variable "spot_node_pool" {
  type        = string
  description = "Karpenter NodePool on Spot whose nodes in target_az get the interruption notice."
  default     = "workers"
}

variable "disruption_duration" {
  type        = string
  description = "ISO 8601 duration of the AZ network disruption."
  default     = "PT10M"

  validation {
    condition     = can(regex("^PT([0-9]+H)?([0-9]+M)?([0-9]+S)?$", var.disruption_duration))
    error_message = "disruption_duration must be an ISO 8601 duration such as PT10M."
  }
}

variable "memorydb_cluster_name" {
  type        = string
  description = "MemoryDB cluster of the target cell whose shard fails over."
}

variable "memorydb_shard_name" {
  type        = string
  description = "Shard that fails over."
  default     = "0001"
}

variable "eks_pod_actions" {
  type = object({
    cluster_name    = string
    service_account = string
    namespace       = string
    selector        = string
    percent         = optional(number, 50)
  })
  description = "Pod deletion in target_az; null until the FIS role has an EKS access entry and the service account with its RBAC exists in the cluster."
  default     = null
}

variable "psp_latency" {
  type = object({
    namespace    = string
    selector     = string
    destinations = list(string)
    delay_ms     = optional(number, 2000)
    jitter_ms    = optional(number, 200)
    duration     = optional(string, "PT5M")
    pod_percent  = optional(number, 100)
  })
  description = "Latency on PSP egress through aws:eks:pod-network-latency on the egress pods; needs eks_pod_actions. Network Firewall has no FIS action."
  default     = null

  validation {
    condition     = var.psp_latency == null || length(try(var.psp_latency.destinations, [])) > 0
    error_message = "psp_latency.destinations needs at least one PSP domain or CIDR."
  }

  validation {
    condition     = var.psp_latency == null || var.eks_pod_actions != null
    error_message = "psp_latency needs eks_pod_actions (cluster and service account of the FIS pods)."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention of the experiment log group (PCI DSS 10.5.1: one year)."
  default     = 365
}

variable "log_kms_key_arn" {
  type        = string
  description = "KMS key of the experiment log group; its policy must allow logs.amazonaws.com."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary of the FIS and automation roles; it must allow the network ACL actions of aws:network:disrupt-connectivity."
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
