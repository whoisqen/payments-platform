variable "environments" {
  description = "Environments that send application logs; each gets the data stream logs-app-<env>."
  type        = list(string)
  default     = ["dev", "stage", "prod", "shared-services"]

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[a-z][a-z0-9-]{1,30}$", e))])
    error_message = "environments must be lower-case names."
  }
}

variable "streams" {
  description = "Data stream classes: shards, replicas, rollover (per primary shard size or age), days hot and the day of deletion, counted from rollover."
  type = map(object({
    primary_shards      = number
    replicas            = number
    rollover_shard_size = string
    rollover_age        = string
    hot_days            = number
    delete_after_days   = number
  }))
  default = {
    app   = { primary_shards = 3, replicas = 1, rollover_shard_size = "30gb", rollover_age = "1d", hot_days = 7, delete_after_days = 30 }
    audit = { primary_shards = 3, replicas = 1, rollover_shard_size = "10gb", rollover_age = "1d", hot_days = 30, delete_after_days = 365 }
  }

  validation {
    condition     = toset(keys(var.streams)) == toset(["app", "audit"])
    error_message = "streams must define app and audit."
  }

  validation {
    condition = alltrue([for s in values(var.streams) : (
      can(regex("^[0-9]+gb$", s.rollover_shard_size)) &&
      try(tonumber(trimsuffix(s.rollover_shard_size, "gb")) >= 10 && tonumber(trimsuffix(s.rollover_shard_size, "gb")) <= 50, false)
    )])
    error_message = "rollover_shard_size must be 10gb to 50gb per primary shard."
  }

  validation {
    condition     = alltrue([for s in values(var.streams) : s.hot_days >= 1 && s.delete_after_days > s.hot_days && s.primary_shards >= 1 && s.replicas >= 1])
    error_message = "every stream needs at least one primary and one replica, and is deleted after it leaves the hot tier."
  }
}

variable "groups" {
  description = "Identity provider groups (SAML groups attribute) of the Dashboards roles."
  type = object({
    admin       = string
    sre         = string
    security    = string
    engineering = string
  })
}

variable "master_user_arn" {
  description = "Fine-grained access master role; kept in the all_access mapping that this module owns."
  type        = string
}

variable "app_writer_role_arns" {
  description = "IAM roles that write application logs to logs-app-* (the Logstash IRSA role)."
  type        = list(string)
}

variable "audit_writer_role_arns" {
  description = "IAM roles that write the audit trail to logs-audit (the ingestion pipeline role)."
  type        = list(string)
}

variable "env_reader_role_arns" {
  description = "Admin agent role by environment (config/admin-agent.yaml); each reads only logs-app-<env>."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for e, a in var.env_reader_role_arns : contains(["dev", "stage", "prod"], e) && can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", a))])
    error_message = "env_reader_role_arns maps dev, stage or prod to an IAM role ARN."
  }
}

variable "monitor_role_arns" {
  description = "IAM roles of elasticsearch_exporter; mapped to logs_monitor (cluster:monitor/* and indices:monitor/* only)."
  type        = list(string)
  default     = []
}

variable "grafana_role_arns" {
  description = "IAM roles of Grafana; mapped to logs_grafana (read logs-app-*)."
  type        = list(string)
  default     = []
}
