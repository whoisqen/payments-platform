variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  default     = "shared-services"
  description = "Environment segment of the names; the central log domain lives in shared-services."

  validation {
    condition     = var.environment == "shared-services"
    error_message = "log ingestion belongs to the shared-services account."
  }
}

variable "region" {
  type        = string
  description = "Region of the provider, the domain and the log archive."
}

variable "region_short" {
  type        = string
  description = "Short region code, for example euc1."

  validation {
    condition     = can(regex("^[a-z]{2,3}[0-9]$", var.region_short))
    error_message = "region_short must look like euc1 or use1."
  }
}

variable "account_id" {
  type        = string
  description = "shared-services account of the roles and pipelines."
}

variable "domain_arn" {
  type        = string
  description = "ARN of the central log domain."
}

variable "domain_endpoint" {
  type        = string
  description = "VPC endpoint host of the domain, without scheme."
}

variable "oidc_provider_arn" {
  type        = string
  description = "IAM OIDC provider of the central cluster; the Logstash service account assumes its role through it (IRSA)."
}

variable "logstash_service_account" {
  type = object({
    namespace = optional(string, "monitoring")
    name      = optional(string, "logstash")
  })
  default     = {}
  description = "Service account of Logstash on the central cluster."
}

variable "cluster_name" {
  type        = string
  description = "Central cluster; the Pod Identity associations of the readers are created in it."
}

variable "readers" {
  type = object({
    exporter = optional(object({ namespace = string, service_account = string }), { namespace = "monitoring", service_account = "opensearch-exporter" })
    grafana  = optional(object({ namespace = string, service_account = string }), { namespace = "monitoring", service_account = "grafana" })
  })
  default     = {}
  description = "Service accounts of the readers on the central cluster: the OpenSearch metrics exporter and Grafana."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary policy attached to every role."
}

variable "log_archive" {
  type = object({
    bucket_name = string
    account_id  = string
    prefixes    = optional(map(string), { cloudtrail = "cloudtrail/AWSLogs/", eks = "eks/" })
  })
  description = "Log archive bucket (log-archive account) and the prefixes of the audit sources: CloudTrail and the EKS control-plane export."

  validation {
    condition     = toset(keys(var.log_archive.prefixes)) == toset(["cloudtrail", "eks"])
    error_message = "log_archive.prefixes must name cloudtrail and eks."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets of the pipelines; they reach the VPC-only domain from there."
}

variable "client_security_group_id" {
  type        = string
  description = "Client security group of the domain (opensearch output client_security_group_id)."
}

variable "kms_key_arn" {
  type        = string
  description = "Key of the pipeline buffers at rest."
}

variable "logs_kms_key_arn" {
  type        = string
  description = "Key of the pipeline log group; its policy admits logs.amazonaws.com."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Days the pipeline logs stay in CloudWatch."

  validation {
    condition     = var.log_retention_days >= 1
    error_message = "log_retention_days must be at least 1."
  }
}

variable "audit_stream" {
  type        = string
  default     = "logs-audit"
  description = "Data stream of the audit trail."
}

variable "units" {
  type = object({
    min = optional(number, 1)
    max = optional(number, 4)
  })
  default     = {}
  description = "Ingestion OCUs of each pipeline."
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
