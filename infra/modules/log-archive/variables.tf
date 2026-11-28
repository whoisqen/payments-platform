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
  description = "Short region code (name pay-<env>-<region-short>-<component>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "component" {
  description = "Component segment of the bucket and key names."
  type        = string
  default     = "log-archive"
}

variable "account_id" {
  description = "Log-archive account that owns the bucket and key."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "organization_id" {
  description = "Organization whose accounts may deliver Config and VPC Flow Logs (aws:SourceOrgID)."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must look like o-abcdefghij."
  }
}

variable "management_account_id" {
  description = "Management account that owns the organization trail."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be 12 digits."
  }
}

variable "trail_arn" {
  description = "ARN of the organization trail; built from its name so this stack does not depend on the trail stack."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:cloudtrail:[a-z0-9-]+:[0-9]{12}:trail/.+$", var.trail_arn))
    error_message = "trail_arn must be a CloudTrail trail ARN."
  }
}

variable "reader_principal_arns" {
  description = "IAM principals (audit account roles) allowed to read and decrypt the logs."
  type        = list(string)
  default     = []
}

variable "ingest_reader_principal_arns" {
  description = "Roles of the central log ingestion (shared-services) that read the cloudtrail and eks prefixes and decrypt through S3."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.ingest_reader_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", a))])
    error_message = "ingest_reader_principal_arns must be IAM role ARNs."
  }
}

variable "ingest_notifications" {
  description = "SQS queue (shared-services, log-ingestion output queue_arns) notified of new objects under each key prefix."
  type = map(object({
    prefix    = string
    queue_arn = string
  }))
  default = {}

  validation {
    condition     = alltrue([for n in values(var.ingest_notifications) : can(regex("^arn:aws:sqs:[a-z0-9-]+:[0-9]{12}:.+$", n.queue_arn))])
    error_message = "ingest_notifications queue_arn must be an SQS queue ARN."
  }
}

variable "prefixes" {
  description = "Key prefix of each log source in the bucket."
  type = object({
    cloudtrail = string
    config     = string
    flow_logs  = string
    eks        = optional(string, "eks")
  })
  default = {
    cloudtrail = "cloudtrail"
    config     = "config"
    flow_logs  = "flow-logs"
    eks        = "eks"
  }
}

variable "object_lock_days" {
  description = "Default Object Lock retention in COMPLIANCE mode (PCI DSS 10.5.1: one year)."
  type        = number
  default     = 365

  validation {
    condition     = var.object_lock_days >= 365
    error_message = "object_lock_days must be at least 365 (PCI DSS 10.5.1)."
  }
}

variable "glacier_after_days" {
  description = "Age at which log objects move to Glacier Flexible Retrieval; the last 90 days stay immediately readable."
  type        = number
  default     = 90

  validation {
    condition     = var.glacier_after_days >= 90
    error_message = "glacier_after_days must be at least 90 so three months stay immediately available."
  }
}

variable "expiration_days" {
  description = "Age at which log objects expire; never before the lock ends."
  type        = number
  default     = 400

  validation {
    condition     = var.expiration_days >= var.object_lock_days
    error_message = "expiration_days must not be shorter than object_lock_days."
  }
}

variable "access_log_expiration_days" {
  description = "Age at which server access log objects expire."
  type        = number
  default     = 400
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the key is deleted."
  type        = number
  default     = 30
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
