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
  default     = "egress"
  description = "Last part of the resource name."
}

variable "vpc_id" {
  type        = string
  description = "Egress VPC of the network account."
}

variable "firewall_subnet_ids" {
  type        = list(string)
  description = "Dedicated firewall subnets, one per AZ."

  validation {
    condition     = length(var.firewall_subnet_ids) == 3
    error_message = "firewall_subnet_ids needs one subnet in each of the three AZs."
  }
}

variable "nat_subnet_ids" {
  type        = list(string)
  description = "Public subnets that hold the NAT gateways, one per AZ."

  validation {
    condition     = length(var.nat_subnet_ids) == 3
    error_message = "nat_subnet_ids needs one subnet in each of the three AZs."
  }
}

variable "psp_domains" {
  type        = list(string)
  description = "PSP domains from infra/network/psp-allowlist.yaml; a leading dot also matches subdomains."

  validation {
    condition     = length(var.psp_domains) > 0 && alltrue([for d in var.psp_domains : can(regex("^\\.?[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", d))])
    error_message = "psp_domains must be a non-empty list of lower-case domain names."
  }
}

variable "rule_group_capacity" {
  type        = number
  default     = 1000
  description = "Capacity of the allowlist rule group; it cannot be changed in place."
}

variable "delete_protection" {
  type        = bool
  default     = true
  description = "Block deletion of the firewall."
}

variable "enable_logging" {
  type        = bool
  default     = false
  description = "Send ALERT and FLOW logs to log_bucket_name; a flag because the bucket name may be unknown at plan time."
}

variable "log_bucket_name" {
  type        = string
  default     = null
  description = "S3 bucket for ALERT and FLOW logs in the log-archive account."

  validation {
    condition     = !var.enable_logging || var.log_bucket_name != null
    error_message = "log_bucket_name is required when enable_logging is true."
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
