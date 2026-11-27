variable "zone_id" {
  type        = string
  description = "Public hosted zone that holds record_name."

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID."
  }
}

variable "record_name" {
  type        = string
  description = "Public API name that clients resolve."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", var.record_name))
    error_message = "record_name must be a lower-case domain name."
  }
}

variable "primary_key" {
  type        = string
  description = "Key of the endpoint that serves all traffic while it is healthy (the working region)."

  validation {
    condition     = contains(keys(var.endpoints), var.primary_key)
    error_message = "primary_key must be a key of endpoints."
  }
}

variable "endpoints" {
  type = map(object({
    target_dns = string
  }))
  description = "Regional ingress names keyed by a short key; exactly one is the primary, the other is the standby."

  validation {
    condition     = length(var.endpoints) == 2
    error_message = "failover needs exactly two endpoints: a primary and a standby."
  }
}

variable "health_check_path" {
  type    = string
  default = "/health/ready"
}

variable "health_check_port" {
  type    = number
  default = 443
}

variable "failure_threshold" {
  type    = number
  default = 3

  validation {
    condition     = var.failure_threshold >= 1 && var.failure_threshold <= 10
    error_message = "failure_threshold must be 1 to 10."
  }
}

variable "request_interval" {
  type    = number
  default = 30

  validation {
    condition     = contains([10, 30], var.request_interval)
    error_message = "request_interval must be 10 or 30 seconds."
  }
}

variable "record_ttl" {
  type    = number
  default = 60

  validation {
    condition     = var.record_ttl >= 10 && var.record_ttl <= 3600
    error_message = "record_ttl must be 10 to 3600 seconds."
  }
}
