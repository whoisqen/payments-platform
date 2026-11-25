variable "instance_arn" {
  type        = string
  description = "ARN of the IAM Identity Center instance in the management account."

  validation {
    condition     = can(regex("^arn:aws:sso:::instance/ssoins-[0-9a-f]+$", var.instance_arn))
    error_message = "instance_arn must be an Identity Center instance ARN."
  }
}

variable "identity_store_id" {
  type        = string
  description = "Identity store of the instance; Okta provisions its users and groups into it through SCIM."

  validation {
    condition     = can(regex("^d-[0-9a-f]{10}$", var.identity_store_id))
    error_message = "identity_store_id must look like d-0123456789."
  }
}

variable "accounts" {
  type        = map(string)
  description = "Account key => 12-digit account id of every account people may enter."

  validation {
    condition     = alltrue([for id in values(var.accounts) : can(regex("^[0-9]{12}$", id))])
    error_message = "every account id must be 12 digits."
  }
}

variable "management_account" {
  type        = string
  description = "Key of the management account in accounts; the only account that takes the Admin permission set."
  default     = "management"
}

variable "cde_accounts" {
  type        = list(string)
  description = "Keys of the accounts that hold the CDE; SRE-CDE reaches only these, and only through cde_jit_grants."
}

variable "sre_view_permission_set" {
  type        = string
  description = "Name of the view-only permission set; the EKS access entries derive the role name AWSReservedSSO_<name> from it."
  default     = "SRE-View"
}

variable "sre_view_groups" {
  type        = list(string)
  description = "Identity store groups that get SRE-View in every account."
}

variable "assignments" {
  type        = map(map(list(string)))
  description = "Standing access: account key => permission set name => identity store group names. SRE-CDE is never standing."
  default     = {}

  validation {
    condition     = alltrue([for a, sets in var.assignments : contains(keys(var.accounts), a)])
    error_message = "assignments may only name accounts listed in accounts."
  }

  validation {
    condition     = alltrue(flatten([for a, sets in var.assignments : [for ps in keys(sets) : contains(["Admin", "PlatformAdmin", var.sre_view_permission_set, "ReadOnly", "Billing"], ps)]]))
    error_message = "assignments may use Admin, PlatformAdmin, SRE-View, ReadOnly and Billing; SRE-CDE is granted only through cde_jit_grants."
  }

  validation {
    condition     = alltrue([for a, sets in var.assignments : a == var.management_account || !contains(keys(sets), "Admin")])
    error_message = "Admin may be assigned in the management account only."
  }

  validation {
    condition     = !contains(keys(lookup(var.assignments, var.management_account, {})), "PlatformAdmin")
    error_message = "the management account takes Admin, not PlatformAdmin."
  }
}

variable "cde_jit_grants" {
  type = list(object({
    account    = string
    group      = optional(string)
    user       = optional(string)
    expires_at = string
    reason     = string
  }))
  description = "Just-in-time SRE-CDE access: account key, one group or user of the identity store, RFC 3339 expiry at most 1 h ahead, reason (incident or ticket)."
  default     = []

  validation {
    condition     = alltrue([for g in var.cde_jit_grants : (g.group == null) != (g.user == null)])
    error_message = "every grant names exactly one of group or user."
  }

  validation {
    condition     = alltrue([for g in var.cde_jit_grants : can(timecmp(g.expires_at, "2000-01-01T00:00:00Z"))])
    error_message = "expires_at must be an RFC 3339 timestamp such as 2026-11-25T14:00:00Z."
  }

  validation {
    condition     = alltrue([for g in var.cde_jit_grants : contains(var.cde_accounts, g.account) && contains(keys(var.accounts), g.account)])
    error_message = "grants may only name accounts listed in both cde_accounts and accounts."
  }

  validation {
    condition     = alltrue([for g in var.cde_jit_grants : length(trimspace(g.reason)) > 0])
    error_message = "every grant needs a reason (incident or ticket)."
  }
}

variable "revocation_run" {
  type        = bool
  description = "Set only by the scheduled revocation run: expired grants are dropped (their assignments destroyed) instead of failing the plan."
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
