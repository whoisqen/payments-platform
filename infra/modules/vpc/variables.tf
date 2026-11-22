variable "region" {
  type        = string
  description = "Region of the provider this module instance runs in."

  validation {
    condition     = contains(["eu-central-1", "us-east-1", "us-east-2"], var.region)
    error_message = "region must be eu-central-1, us-east-1 or us-east-2."
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
  default     = "vpc"
  description = "Last part of the resource name, for example vpc-cde or vpc-platform."
}

variable "cidr_block" {
  type        = string
  description = "VPC CIDR from IPAM, for example 10.100.0.0/16."

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid CIDR."
  }
}

variable "azs" {
  type        = list(string)
  description = "Exactly three availability zones; subnet lists are matched to them by index."

  validation {
    condition     = length(var.azs) == 3
    error_message = "azs must hold exactly three zones."
  }
}

variable "subnet_cidrs" {
  type = object({
    public  = optional(list(string), [])
    private = list(string)
    data    = list(string)
  })
  description = "CIDRs per tier, one per AZ; the public tier is empty or three entries (NLB ingress subnets in the CDE)."

  validation {
    condition     = length(var.subnet_cidrs.private) == 3 && length(var.subnet_cidrs.data) == 3 && contains([0, 3], length(var.subnet_cidrs.public))
    error_message = "private and data need three CIDRs; public needs zero or three."
  }
}

variable "enable_internet_gateway" {
  type        = bool
  default     = false
  description = "Attach an internet gateway to the public tier; must stay false in the CDE (SCP denies it)."
}

variable "enable_egress_route" {
  type        = bool
  default     = false
  description = "Send 0.0.0.0/0 of the private tier to egress_transit_gateway_id; a flag because the id may be unknown at plan time."
}

variable "egress_transit_gateway_id" {
  type        = string
  default     = null
  description = "Transit gateway of the network account (egress with Network Firewall); its VPC attachment must exist before the route."

  validation {
    condition     = !var.enable_egress_route || var.egress_transit_gateway_id != null
    error_message = "egress_transit_gateway_id is required when enable_egress_route is true."
  }
}

variable "gateway_endpoint_services" {
  type        = list(string)
  default     = ["s3", "dynamodb"]
  description = "Gateway endpoints attached to the private and data route tables."
}

variable "interface_endpoint_services" {
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "kms", "secretsmanager", "ssm", "ssmmessages", "ec2messages", "logs"]
  description = "Interface endpoints created in the private tier; AWS APIs are reached only through them in the CDE."
}

variable "flow_logs_bucket_arn" {
  type        = string
  description = "S3 bucket (log-archive account, Object Lock) that receives the VPC flow logs."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
