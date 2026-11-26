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
  description = "PSP domains from infra/network/psp-allowlist.yaml; a leading dot also matches subdomains. Empty (no PSP rule group) only for an egress VPC that serves CI runners."

  validation {
    condition     = (length(var.psp_domains) > 0 || length(var.ci_source_cidrs) > 0) && alltrue([for d in var.psp_domains : can(regex("^\\.?[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", d))])
    error_message = "psp_domains must be lower-case domain names, and may be empty only when ci_source_cidrs is set."
  }
}

variable "ci_source_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs of the CI runners, trusted and untrusted (the shared-services VPC); empty creates no CI allowlist."

  validation {
    condition     = alltrue([for c in var.ci_source_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "ci_source_cidrs must be CIDRs of the runner subnets, never 0.0.0.0/0."
  }
}

variable "ci_domains" {
  type = list(string)
  default = [
    "github.com", "api.github.com", "codeload.github.com", ".actions.githubusercontent.com", "objects.githubusercontent.com",
    "release-assets.githubusercontent.com", "ghcr.io", "pkg-containers.githubusercontent.com", ".blob.core.windows.net",
    "autoscaling.eu-central-1.amazonaws.com", "pypi.org", "files.pythonhosted.org", "registry.npmjs.org", "crates.io",
    "static.crates.io", "index.crates.io", "mise.jdx.dev", "mise-versions.jdx.dev",
  ]
  description = "Domains the untrusted CI runners may reach: GitHub (Actions, releases, ghcr), Actions storage, the Auto Scaling API and the package registries of the jobs; a leading dot also matches subdomains."

  validation {
    condition     = length(var.ci_domains) > 0 && alltrue([for d in var.ci_domains : can(regex("^\\.?[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", d))])
    error_message = "ci_domains must be a non-empty list of lower-case domain names."
  }
}

variable "ci_trusted_source_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDRs of the trusted CI runner pools (vpc output private_cidr_blocks); they may also reach ci_trusted_domains. Empty creates no rule group."

  validation {
    condition     = alltrue([for c in var.ci_trusted_source_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "ci_trusted_source_cidrs must be CIDRs of the runner subnets, never 0.0.0.0/0."
  }
}

variable "ci_trusted_domains" {
  type = list(string)
  default = [
    "sts.amazonaws.com", "iam.amazonaws.com", "route53.amazonaws.com", "globalaccelerator.amazonaws.com", "tagging.eu-central-1.amazonaws.com",
    "ec2.eu-central-1.amazonaws.com", "elasticloadbalancing.eu-central-1.amazonaws.com", "acm.eu-central-1.amazonaws.com",
    "network-firewall.eu-central-1.amazonaws.com", "ram.eu-central-1.amazonaws.com", "rds.eu-central-1.amazonaws.com",
    "elasticache.eu-central-1.amazonaws.com", "memory-db.eu-central-1.amazonaws.com", "dynamodb.eu-central-1.amazonaws.com",
  ]
  description = "AWS API domains without an interface endpoint in the CI VPC that the trusted pools need (the read-only Terraform plan of the environment accounts); a leading dot also matches subdomains."

  validation {
    condition     = length(var.ci_trusted_domains) <= 90 && alltrue([for d in var.ci_trusted_domains : can(regex("^\\.?[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", d))])
    error_message = "ci_trusted_domains must be at most 90 lower-case domain names."
  }
}

variable "ci_rule_group_capacity" {
  type        = number
  default     = 200
  description = "Capacity of the CI allowlist rule group; it cannot be changed in place."
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

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name, for example the project short name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}
