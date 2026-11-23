variable "region" {
  type        = string
  description = "Recovery region of the provider this instance runs in."

  validation {
    condition     = contains(["us-east-1", "us-east-2"], var.region)
    error_message = "region must be us-east-1 or us-east-2."
  }
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "account_id" {
  type        = string
  description = "Account id, a suffix that makes the bucket name globally unique."
}

variable "component" {
  type        = string
  default     = "tf-state"
  description = "Last part of the bucket name."
}

variable "kms_key_arn" {
  type        = string
  description = "Replica KMS key of this region."
}

variable "retention_days" {
  type        = number
  default     = 365
  description = "Governance retention of every object version."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22."
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
