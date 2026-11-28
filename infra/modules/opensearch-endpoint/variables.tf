variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "env" {
  type        = string
  description = "Environment of the VPC that gets the endpoint."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env must be dev, stage or prod."
  }
}

variable "region_short" {
  type        = string
  description = "Short region code, for example euc1."

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "domain_arn" {
  type        = string
  description = "ARN of the central log domain in shared-services; its owner authorizes this account (opensearch endpoint_account_ids)."

  validation {
    condition     = can(regex("^arn:aws:es:[a-z0-9-]+:[0-9]{12}:domain/[a-z][a-z0-9-]{2,27}$", var.domain_arn))
    error_message = "domain_arn must be an OpenSearch domain ARN."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC of the endpoint."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets of the endpoint, one per AZ."
}

variable "client_cidr_blocks" {
  type        = list(string)
  description = "CIDRs admitted on 443, normally the VPC CIDR (the admin agent path of the environment)."

  validation {
    condition     = length(var.client_cidr_blocks) > 0 && alltrue([for c in var.client_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "client_cidr_blocks must list valid CIDRs."
  }
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
