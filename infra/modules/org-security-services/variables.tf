variable "mode" {
  description = "management designates the audit account as delegated administrator; admin (the audit account) configures the services for the organization."
  type        = string

  validation {
    condition     = contains(["management", "admin"], var.mode)
    error_message = "mode must be management or admin."
  }
}

variable "name_prefix" {
  description = "Prefix of the resource names."
  type        = string
  default     = "pay"
}

variable "env" {
  description = "Environment segment of the resource name."
  type        = string
  default     = "security"
}

variable "region_short" {
  description = "Short region code of the home region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "region_name" {
  description = "Home region: Security Hub aggregation and central configuration, Macie jobs."
  type        = string
}

variable "regions" {
  description = "Regions where the services run (the region allow list of the SCP); must contain region_name."
  type        = list(string)
}

variable "admin_account_id" {
  description = "Audit account: delegated administrator of every service."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.admin_account_id))
    error_message = "admin_account_id must be 12 digits."
  }
}

variable "root_id" {
  description = "Organization root (r-...) that the Security Hub configuration policy is associated with."
  type        = string
  default     = ""
}

variable "member_account_ids" {
  description = "Existing member accounts that Inspector associates and enables; auto-enable covers only accounts created later."
  type        = list(string)
  default     = []
}

variable "cde_account_ids" {
  description = "CDE accounts whose S3 buckets the Macie job scans daily for card data; empty skips the job."
  type        = list(string)
  default     = []
}

variable "guardduty_enabled" {
  description = "Manage GuardDuty."
  type        = bool
  default     = true
}

variable "guardduty_features" {
  description = "GuardDuty features enabled for every account, with their additional configuration."
  type        = map(list(string))
  default = {
    S3_DATA_EVENTS         = []
    EKS_AUDIT_LOGS         = []
    EBS_MALWARE_PROTECTION = []
    RDS_LOGIN_EVENTS       = []
    LAMBDA_NETWORK_LOGS    = []
    RUNTIME_MONITORING     = ["EKS_ADDON_MANAGEMENT"]
  }
}

variable "securityhub_enabled" {
  description = "Manage Security Hub."
  type        = bool
  default     = true
}

variable "securityhub_standards" {
  description = "Standards of the central configuration policy, as <path>/v/<version> after standards/."
  type        = list(string)
  default = [
    "pci-dss/v/4.0.1",
    "aws-foundational-security-best-practices/v/1.0.0",
    "cis-aws-foundations-benchmark/v/3.0.0",
  ]
}

variable "inspector_enabled" {
  description = "Manage Inspector."
  type        = bool
  default     = true
}

variable "inspector_resource_types" {
  description = "Inspector scan types."
  type        = list(string)
  default     = ["EC2", "ECR", "LAMBDA", "LAMBDA_CODE"]
}

variable "macie_enabled" {
  description = "Manage Macie."
  type        = bool
  default     = true
}

variable "shield_advanced_enabled" {
  description = "Subscribe the account this stack runs in to Shield Advanced (one-year commitment, monthly fee paid once per billing family)."
  type        = bool
  default     = false
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
