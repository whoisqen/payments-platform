variable "name_prefix" {
  type        = string
  description = "Naming prefix (pay)."
}

variable "environment" {
  type        = string
  description = "Environment of the account; FIS runs in stage, prod only for a game day."

  validation {
    condition     = contains(["stage", "prod"], var.environment)
    error_message = "environment must be stage or prod."
  }
}

variable "region" {
  type        = string
  description = "Region of the experiments and of the chaos-stop alarm."
}

variable "region_short" {
  type        = string
  description = "Short region name used in resource names (euc1)."
}

variable "account_id" {
  type        = string
  description = "Account that runs the experiments."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account id."
  }
}

variable "boundary_name" {
  type        = string
  description = "Name of the permissions boundary; fis-experiments falls back to this name when it has no dependency output."
  default     = "fis-experiment-boundary"
}

variable "stop_signal" {
  type = object({
    namespace   = optional(string, "Payments/Chaos")
    metric_name = optional(string, "StopSignal")
  })
  description = "Custom metric the Alertmanager bridge publishes per environment (1 while a burn-rate 14.4 or AuthorizationRateDrop alert fires, else 0)."
  default     = {}
}

variable "stop_signal_missing_data" {
  type        = string
  description = "Missing data of the stop signal; breaching keeps experiments from starting while the bridge is silent."
  default     = "breaching"

  validation {
    condition     = contains(["breaching", "notBreaching"], var.stop_signal_missing_data)
    error_message = "stop_signal_missing_data must be breaching or notBreaching."
  }
}

variable "edge_target_groups" {
  type = list(object({
    key           = string
    load_balancer = string
    target_group  = string
    min_healthy   = number
  }))
  description = "NLB target groups of the payments edge (ARN suffixes, net/... and targetgroup/...): alarm when healthy targets across all AZs stay below min_healthy for 3 min."
  default     = []

  validation {
    condition     = alltrue([for t in var.edge_target_groups : startswith(t.load_balancer, "net/") && startswith(t.target_group, "targetgroup/") && t.min_healthy >= 1])
    error_message = "edge_target_groups need NLB ARN suffixes (net/..., targetgroup/...) and min_healthy of at least 1."
  }
}

variable "aurora_cluster_ids" {
  type        = list(string)
  description = "Aurora clusters of the environment: alarm when a cluster reports no writer for aurora_writer_minutes, longer than a failover takes."
  default     = []
}

variable "aurora_writer_minutes" {
  type        = number
  description = "Minutes without a writer metric before the Aurora child alarm fires; above the 2 min of the failover hypothesis."
  default     = 5

  validation {
    condition     = var.aurora_writer_minutes >= 3
    error_message = "aurora_writer_minutes must be at least 3 so a normal failover does not stop its own experiment."
  }
}

variable "additional_alarm_arns" {
  type        = list(string)
  description = "Existing CloudWatch alarms of observability that also stop experiments."
  default     = []

  validation {
    condition     = alltrue([for a in var.additional_alarm_arns : startswith(a, "arn:aws:cloudwatch:")])
    error_message = "additional_alarm_arns must be CloudWatch alarm ARNs."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "SNS topics notified when chaos-stop changes to ALARM."
  default     = []
}

variable "eks_access_entry" {
  type = object({
    cluster_name = string
    username     = optional(string, "fis-experiment")
  })
  description = "EKS access entry of the FIS role for pod actions; set after fis-experiments created the role, EKS rejects a principal that does not exist."
  default     = null
}

variable "msk_cluster_name" {
  type        = string
  description = "MSK cluster of the msk-broker-loss experiment (pay-<env>-<rs>-msk); null creates no reboot document."
  default     = null
}

variable "automation_role_exists" {
  type        = bool
  description = "Set after fis-experiments created <name>-chaos-automation; adds the MSK reboot policy to that role."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
