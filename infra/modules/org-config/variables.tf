variable "mode" {
  description = "management registers the delegated administrator; admin (the audit account) builds the aggregator, recorders and conformance pack."
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
  description = "Home region: aggregator, global resource recording and the stack set."
  type        = string
}

variable "regions" {
  description = "Regions with a recorder and the conformance pack (the region allow list of the SCP)."
  type        = list(string)
}

variable "admin_account_id" {
  description = "Audit account: delegated administrator of Config and of service-managed stack sets."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.admin_account_id))
    error_message = "admin_account_id must be 12 digits."
  }
}

variable "recorder_stack_set_enabled" {
  description = "Deploy a Config recorder and delivery channel to every account of recorder_target_ou_ids; false where Control Tower already owns the recorders."
  type        = bool
  default     = true
}

variable "recorder_target_ou_ids" {
  description = "OUs (or the root) whose accounts get a recorder through the stack set; new accounts get one automatically."
  type        = list(string)
  default     = []
}

variable "create_service_linked_role" {
  description = "Create AWSServiceRoleForConfig in the home region stack; false when the role already exists in the accounts."
  type        = bool
  default     = true
}

variable "delivery_bucket_name" {
  description = "Log archive bucket for configuration snapshots and history (output bucket_name of log-archive)."
  type        = string
  default     = ""
}

variable "delivery_key_prefix" {
  description = "Prefix of Config in the log archive bucket."
  type        = string
  default     = "config"
}

variable "delivery_kms_key_arn" {
  description = "Key of the log archive bucket (output kms_key_arn of log-archive)."
  type        = string
  default     = ""
}

variable "conformance_pack_name" {
  description = "Name of the organization conformance pack."
  type        = string
  default     = "pci-dss-v4"
}

variable "conformance_pack_template" {
  description = "Template body of the conformance pack (policy/config/pci-dss-pack/pci-dss-v4.yaml); empty skips the pack."
  type        = string
  default     = ""
}

variable "conformance_pack_excluded_accounts" {
  description = "Accounts left out of the conformance pack."
  type        = list(string)
  default     = []
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
