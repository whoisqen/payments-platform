variable "name_prefix" {
  type        = string
  description = "naming.prefix of config/platform.yaml."
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "account_id" {
  type        = string
  description = "Account of the environment."
}

variable "region" {
  type        = string
  description = "Working region."
}

variable "admin_role_arn" {
  type        = string
  description = "The Bedrock admin agent role of shared-services (bedrock-access); the only principal that may assume this role."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.admin_role_arn))
    error_message = "admin_role_arn must be an IAM role ARN."
  }
}

variable "opensearch_domain_arn" {
  type        = string
  description = "ARN of the central OpenSearch domain; the role may only search (fine-grained access control limits it to logs-app-<env>)."
}

variable "log_group_names" {
  type        = list(string)
  description = "CloudWatch log groups the agent may read (log_groups of config/admin-agent.yaml)."
}

variable "clusters" {
  type = map(object({
    namespaces = list(string)
  }))
  description = "EKS cluster name -> namespaces the agent may view (read-only, no Secrets: AmazonEKSViewPolicy scoped to the namespaces)."

  validation {
    condition     = alltrue([for c in values(var.clusters) : length(c.namespaces) > 0])
    error_message = "every cluster names at least one namespace; cluster-wide view is never granted."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "workload-boundary of the account."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22."
}
