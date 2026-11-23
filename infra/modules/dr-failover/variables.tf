variable "env" {
  description = "Environment segment of the resource name."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env must be dev, stage or prod."
  }
}

variable "region_short" {
  description = "Short region code of the standby region (the provider region), for example use1 (name pay-<env>-<region-short>-<component>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "tags" {
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }

  validation {
    condition = (
      contains(["payments-core", "platform", "security", "data"], lookup(var.tags, "team", "")) &&
      contains(["cde", "connected", "out-of-scope"], lookup(var.tags, "pci-scope", "")) &&
      contains(["card-data", "pii", "internal", "public"], lookup(var.tags, "data-class", "")) &&
      contains(["gold", "silver", "bronze", "none"], lookup(var.tags, "backup-tier", ""))
    )
    error_message = "tags team, pci-scope, data-class or backup-tier is outside the section 22.1 schema."
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

variable "account_id" {
  description = "Account of the environment; builds IAM resource ARNs without a data source."
  type        = string
}

variable "source_region" {
  description = "Working region whose health check triggers the failover."
  type        = string
}

variable "source_region_short" {
  description = "Short code of the working region; names the Aurora global clusters (pay-<env>-<short>-aurora-<cell>)."
  type        = string
}

variable "fallback_region" {
  description = "Second recovery region that holds the lock record if the standby cannot be used."
  type        = string
}

variable "cells" {
  description = "Names whose Aurora global cluster is promoted: the cells, the spare and locker."
  type        = list(string)

  validation {
    condition     = length(var.cells) > 0
    error_message = "at least one cell is needed."
  }
}

variable "health_check_id" {
  description = "Route 53 health check of the working region ingress (output of dns-routing)."
  type        = string
}

variable "deny_policy_arn" {
  description = "IAM policy that denies DynamoDB writes in the standby region; the failover removes the standby region from it."
  type        = string
  default     = ""
}

variable "fence_rule_group" {
  description = "Network Firewall rule group of the working region that blocks PSP traffic when the region is fenced."
  type        = string
}

variable "kms_key_arn" {
  description = "Key of the lock table in the standby region."
  type        = string
}

variable "alarm_evaluation_periods" {
  description = "Consecutive one-minute periods with a failing health check before the failover starts."
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_evaluation_periods >= 3 && var.alarm_evaluation_periods <= 30
    error_message = "alarm_evaluation_periods must be 3 to 30."
  }
}

variable "notification_topic_arns" {
  description = "Extra SNS topics (on-call) told that a failover started."
  type        = list(string)
  default     = []
}

variable "component" {
  description = "Component segment of the name."
  type        = string
  default     = "dr-failover"
}
