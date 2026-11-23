variable "name_prefix" {
  description = "Name prefix from config/platform.yaml (naming.prefix)."
  type        = string
}

variable "env" {
  description = "Environment segment of the resource name."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env must be dev, stage or prod."
  }
}

variable "region_short" {
  description = "Short region code of the provider region, for example use2."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "component" {
  description = "Component segment of the name."
  type        = string
  default     = "restore-test"
}

variable "resource_types" {
  description = "Backup resource types whose finished restore jobs trigger the automation."
  type        = list(string)
  default     = ["Aurora", "DynamoDB"]
}

variable "target_seconds" {
  description = "Restore duration target; the 80% alert threshold is derived from it by the alert rules (D4: 30 minutes)."
  type        = number
  default     = 1800

  validation {
    condition     = var.target_seconds > 0
    error_message = "target_seconds must be positive."
  }
}

variable "metric_namespace" {
  description = "CloudWatch namespace of the restore metrics that the backup exporter reads."
  type        = string
  default     = "Payments/Backup"
}

variable "validator_lambda_arn" {
  description = "Validator Lambda of the platform stack (schema version, payment count, last transaction age); null skips validation."
  type        = string
  default     = null
}

variable "tags" {
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
