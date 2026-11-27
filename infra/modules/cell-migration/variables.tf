variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; naming.prefix of config/platform.yaml."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
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

variable "region" {
  type        = string
  description = "Working region; the documents and the copy function run here."
}

variable "region_short" {
  type        = string
  description = "Short region code, for example euc1."
}

variable "account_id" {
  type        = string
  description = "Account of the environment."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}

variable "cells" {
  type = map(object({
    proxy_endpoint          = string
    proxy_security_group_id = string
    login_secret_arn        = string
  }))
  description = "Cell -> RDS Proxy endpoint, its security group (data-access aurora-proxy) and the hs_app login secret; the copy function reads one cell and writes another."

  validation {
    condition     = alltrue([for c in keys(var.cells) : can(regex("^(cell-[0-3]|spare)$", c))])
    error_message = "cells are cell-0 to cell-3 and spare."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC of the cells."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets of the copy function."
}

variable "image_uri" {
  type        = string
  default     = null
  description = "Image of the copy function by digest (<registry>/<repo>@sha256:...); null creates the documents only, and they fail at the invoke step."

  validation {
    condition     = var.image_uri == null || can(regex("@sha256:[a-f0-9]{64}$", var.image_uri))
    error_message = "image_uri must be pinned by digest."
  }
}

variable "secrets_kms_key_arns" {
  type        = list(string)
  description = "Keys of the login secrets (the key of each cell)."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "workload-boundary of the account."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
