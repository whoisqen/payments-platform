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
  default     = "edge"
  description = "Last part of the resource name."
}

variable "listener_ports" {
  type        = list(number)
  default     = [443]
  description = "TCP ports of the listener."
}

variable "endpoint_groups" {
  type = map(object({
    active                = bool
    endpoint_arns         = optional(list(string), [])
    health_check_protocol = optional(string, "HTTPS")
    health_check_port     = optional(number, 443)
    health_check_path     = optional(string, "/health/deep")
  }))
  description = "Endpoint group per region; only the writing region is active, recovery groups have weight 0 and dial 0 and usually no endpoints."

  validation {
    condition     = alltrue([for r in keys(var.endpoint_groups) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "endpoint group keys must be AWS region names."
  }

  validation {
    condition     = length([for g in values(var.endpoint_groups) : g if g.active]) <= 1
    error_message = "at most one group may be active: two writing regions could charge a payment twice."
  }
}

variable "flow_logs_bucket" {
  type        = string
  default     = null
  description = "S3 bucket name for accelerator flow logs; null disables them."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
