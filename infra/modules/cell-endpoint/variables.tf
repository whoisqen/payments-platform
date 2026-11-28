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
  description = "Region of the provider."
}

variable "region_short" {
  type        = string
  description = "Short region code, for example euc1."
}

variable "account_id" {
  type        = string
  description = "Account of the VPC; scopes the controller role trust."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be 12 digits."
  }
}


variable "vpc_id" {
  type        = string
  description = "VPC shared by the edge cluster and the cell clusters of this region."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private app subnets, one per AZ; the load balancer is internal."
}

variable "cluster_domain" {
  type        = string
  description = "deploy.<env>.cluster_domain of config/platform.yaml; the record is router.payments.svc.<cell>.<cluster_domain>, the host the edge routes to."
}

variable "cell" {
  type        = string
  description = "Cell of this endpoint (cell-0..cell-3, spare)."

  validation {
    condition     = can(regex("^(cell-[0-3]|spare)$", var.cell))
    error_message = "cell must be cell-0 to cell-3 or spare."
  }
}

variable "port" {
  type        = number
  default     = 8443
  description = "Port of the mutual-TLS router gateway of the cell; listener and target port."
}

variable "client_security_group_ids" {
  type        = list(string)
  description = "Node security groups of the edge cluster; the only callers the load balancer admits."
}

variable "cell_cluster_name" {
  type        = string
  description = "Cluster of the cell; its aws-load-balancer-controller registers the gateway pods through a TargetGroupBinding."
}

variable "cell_cluster_arn" {
  type        = string
  description = "ARN of the cell cluster; the controller role trusts pods of this cluster only."
}

variable "target_security_group_id" {
  type        = string
  description = "Node security group of the cell cluster (eks output node_security_group_id); it admits the load balancer on port."
}

variable "permissions_boundary_arn" {
  type        = string
  description = "workload-boundary of the account."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22."
}
