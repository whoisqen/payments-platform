variable "name_prefix" {
  type        = string
  description = "Prefix of resource names; set from config/platform.yaml (naming.prefix)."

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

variable "scope" {
  type        = string
  default     = "CLOUDFRONT"
  description = "CLOUDFRONT for the panel and SDK distributions (the stack then runs in us-east-1) or REGIONAL for an ALB or API Gateway stage."

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}

variable "mode" {
  type        = string
  default     = "count"
  description = "count only labels and counts matches; block enforces. Start with count, switch to block once the sampled requests are clean."

  validation {
    condition     = contains(["count", "block"], var.mode)
    error_message = "mode must be count or block."
  }
}

variable "count_overrides" {
  type        = map(list(string))
  default     = {}
  description = "Rules kept in count while their group blocks, by group (common, bad-inputs, sqli, ip-reputation, bot-control, atp) -> rule names, for example { common = [\"SizeRestrictions_BODY\"] }."

  validation {
    condition     = alltrue([for k in keys(var.count_overrides) : contains(["common", "bad-inputs", "sqli", "ip-reputation", "bot-control", "atp"], k)])
    error_message = "count_overrides keys must be common, bad-inputs, sqli, ip-reputation, bot-control or atp."
  }
}

variable "entries" {
  type = map(object({
    bot_control    = optional(bool, false)
    atp            = optional(bool, false)
    login_path     = optional(string, "/login")
    username_field = optional(string, "/username")
    password_field = optional(string, "/password")
    auth_paths     = optional(list(string), [])
  }))
  default = {
    panel = { bot_control = true, atp = true, auth_paths = ["/login", "/auth/"] }
    sdk   = {}
  }
  description = "One web ACL per public entry (each distribution takes one ACL). bot_control and atp are for the panel only; atp inspects login_path (JSON body pointers), auth_paths get the stricter rate rule."

  validation {
    condition     = alltrue([for k in keys(var.entries) : can(regex("^[a-z][a-z0-9-]{1,20}$", k))])
    error_message = "entry keys must be lower-case kebab-case."
  }

  validation {
    condition     = alltrue([for e in values(var.entries) : !e.atp || startswith(e.login_path, "/")])
    error_message = "login_path must start with /."
  }
}

variable "rate_limit_ip" {
  type        = number
  default     = 2000
  description = "Requests per evaluation window from one source IP."

  validation {
    condition     = var.rate_limit_ip >= 10
    error_message = "WAF accepts a rate limit of at least 10."
  }
}

variable "rate_limit_api_key" {
  type        = number
  default     = 1000
  description = "Requests per evaluation window for one value of the API key header and, separately, of the merchant header."

  validation {
    condition     = var.rate_limit_api_key >= 10
    error_message = "WAF accepts a rate limit of at least 10."
  }
}

variable "rate_limit_auth" {
  type        = number
  default     = 100
  description = "Requests per evaluation window from one source IP to the authentication paths of the panel."

  validation {
    condition     = var.rate_limit_auth >= 10
    error_message = "WAF accepts a rate limit of at least 10."
  }
}

variable "evaluation_window_sec" {
  type        = number
  default     = 300
  description = "Window of the rate rules; also the Retry-After value of the 429 response."

  validation {
    condition     = contains([60, 120, 300, 600], var.evaluation_window_sec)
    error_message = "evaluation_window_sec must be 60, 120, 300 or 600."
  }
}

variable "api_key_header" {
  type        = string
  default     = "x-api-key"
  description = "Header whose value is the rate key of the per-API-key rule."
}

variable "merchant_header" {
  type        = string
  default     = "x-merchant-id"
  description = "Header whose value is the rate key of the per-merchant rule."
}

variable "redacted_headers" {
  type        = list(string)
  default     = ["authorization", "cookie", "x-api-key"]
  description = "Lower-case request headers that never reach the log."

  validation {
    condition     = alltrue([for h in var.redacted_headers : h == lower(h)]) && alltrue([for h in ["authorization", "cookie", "x-api-key"] : contains(var.redacted_headers, h)])
    error_message = "redacted_headers must be lower-case and include authorization, cookie and x-api-key."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the WAF log groups."
}

variable "kms_key_arn" {
  type        = string
  description = "Key that encrypts the log groups; it must be in the Region of the stack (the logs key of that Region)."
}

variable "tags" {
  type        = map(string)
  description = "Tags of section 22; team, owner, pci-scope, data-class and backup-tier are required."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}
