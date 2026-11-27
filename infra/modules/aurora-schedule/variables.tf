variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "env" {
  type        = string
  description = "Environment segment of the resource name; only dev runs on a schedule (stage keeps secondaries, which AWS cannot stop)."

  validation {
    condition     = var.env == "dev"
    error_message = "only dev Aurora clusters are stopped on a schedule."
  }
}

variable "region_short" {
  type        = string
  description = "Short region code of the clusters, for example euc1."

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1."
  }
}

variable "account_id" {
  type        = string
  description = "Account of the clusters; builds their ARNs."
}

variable "region" {
  type        = string
  description = "Region of the provider and the clusters."
}

variable "component" {
  type        = string
  default     = "aurora-schedule"
  description = "Component segment of the name."
}

variable "cluster_identifiers" {
  type        = list(string)
  description = "Aurora clusters to stop and start; each must be the only cluster of its global database."

  validation {
    condition     = length(var.cluster_identifiers) > 0
    error_message = "at least one cluster is needed."
  }
}

variable "start_cron" {
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
  description = "Start of the working window (section 12: 60 of 168 hours)."
}

variable "stop_cron" {
  type        = string
  default     = "cron(0 20 ? * MON-FRI *)"
  description = "End of the working window; the env-up workflow starts the clusters outside it."
}

variable "timezone" {
  type        = string
  default     = "Europe/Berlin"
  description = "IANA time zone of both expressions."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Customer managed key of the schedule group payloads; null uses the AWS owned key."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
