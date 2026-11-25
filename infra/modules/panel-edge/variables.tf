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

variable "zone_name" {
  type        = string
  description = "Public zone of the environment (config/platform.yaml, dns.<env>_zone); every entry is <subdomain>.<zone_name>."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}$", var.zone_name))
    error_message = "zone_name must be a lower-case domain name."
  }
}

variable "zone_id" {
  type        = string
  description = "Hosted zone id of zone_name (output zone_id of dns-certs); holds the ACM validation and alias records."
}

variable "entries" {
  type = map(object({
    subdomain               = optional(string)
    api_paths               = optional(list(string), ["/api/*"])
    static_paths            = optional(list(string), ["/assets/*", "*.js", "*.css", "*.woff2", "*.svg", "*.png"])
    forward_cookies         = optional(list(string), [])
    frame_deny              = optional(bool, true)
    content_security_policy = optional(string, "default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'")
  }))
  default = {
    panel = {}
    sdk = {
      frame_deny              = false
      content_security_policy = "default-src 'self'; object-src 'none'; base-uri 'self'"
    }
  }
  description = "One distribution per public entry (panel, sdk). subdomain defaults to the key; frame_deny is false for the SDK because merchants embed it in an iframe; content_security_policy is a placeholder until the applications publish theirs."

  validation {
    condition     = alltrue([for k in keys(var.entries) : can(regex("^[a-z][a-z0-9-]{1,20}$", k))])
    error_message = "entry keys must be lower-case kebab-case."
  }

  validation {
    condition     = alltrue(flatten([for e in values(var.entries) : [for p in concat(e.api_paths, e.static_paths) : startswith(p, "/") || startswith(p, "*")]]))
    error_message = "path patterns must start with / or *."
  }

  validation {
    condition     = alltrue([for e in values(var.entries) : length(e.api_paths) + length(e.static_paths) <= 20])
    error_message = "at most 20 path patterns per entry."
  }
}

variable "web_acl_arns" {
  type        = map(string)
  description = "WAF web ACL ARN by entry (output web_acl_arns of waf-edge, CLOUDFRONT scope); every entry must have one."

  validation {
    condition     = alltrue([for k in keys(var.entries) : contains(keys(var.web_acl_arns), k)])
    error_message = "web_acl_arns must hold an ACL for every key of entries."
  }

  validation {
    condition     = alltrue([for a in values(var.web_acl_arns) : can(regex("^arn:aws[a-z-]*:wafv2:us-east-1:[0-9]{12}:global/webacl/", a))])
    error_message = "web_acl_arns must be CLOUDFRONT-scope (global) web ACLs."
  }
}

variable "nlb_lookup_enabled" {
  type        = bool
  default     = false
  description = "Second step of the apply: false creates the certificates, policies and log destination only; true looks up the internal NLB of the Gateway and creates the VPC origin, distributions, alias records and log deliveries."
}

variable "nlb_stack_tag" {
  type        = string
  default     = null
  description = "Value of the tag service.k8s.aws/stack of the NLB, namespace/service-name of the Service the Gateway deploys. Required when nlb_lookup_enabled is true."

  validation {
    condition     = var.nlb_stack_tag == null || can(regex("^[a-z0-9-]+/[a-z0-9.-]+$", var.nlb_stack_tag))
    error_message = "nlb_stack_tag must look like namespace/name."
  }
}

variable "origin_region" {
  type        = string
  default     = "eu-central-1"
  description = "Region of the cluster and its internal NLB (config/platform.yaml, regions.working); only the NLB lookup runs there."
}

variable "nlb_cluster_name" {
  type        = string
  default     = null
  description = "Cluster whose load balancer controller built the NLB (tag elbv2.k8s.aws/cluster); set it when several clusters run a Gateway with the same namespace and name."
}

variable "origin_headers" {
  type        = list(string)
  default     = ["Host", "Origin", "Accept", "Accept-Language", "Content-Type", "X-Request-Id", "api-key", "X-Merchant-Id", "X-Profile-Id"]
  description = "Viewer headers forwarded to the Gateway on dynamic paths. Host is required: the HTTPRoute matches on it and CloudFront checks the origin certificate against it. Authorization travels through the cache key of the API policy instead."

  validation {
    condition     = contains([for h in var.origin_headers : lower(h)], "host") && !contains([for h in var.origin_headers : lower(h)], "authorization")
    error_message = "origin_headers must contain Host and must not contain Authorization (an origin request policy cannot carry it)."
  }
}

variable "static_ttl" {
  type = object({
    min     = optional(number, 0)
    default = optional(number, 300)
    max     = optional(number, 3600)
  })
  default     = {}
  description = "TTL in seconds of the static asset paths; short because the panel ships new bundles with each release."

  validation {
    condition     = var.static_ttl.min <= var.static_ttl.default && var.static_ttl.default <= var.static_ttl.max && var.static_ttl.max <= 86400
    error_message = "static_ttl must satisfy min <= default <= max <= 86400."
  }
}

variable "origin_read_timeout" {
  type        = number
  default     = 30
  description = "Seconds CloudFront waits for a response from the Gateway."

  validation {
    condition     = var.origin_read_timeout >= 1 && var.origin_read_timeout <= 60
    error_message = "origin_read_timeout must be between 1 and 60 without a quota increase."
  }
}

variable "price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "Edge locations served; PriceClass_100 covers Europe and North America."

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "geo_restriction" {
  type = object({
    type      = optional(string, "none")
    locations = optional(list(string), [])
  })
  default     = {}
  description = "none, whitelist or blacklist with ISO 3166-1 alpha-2 country codes; applies to every entry."

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction.type)
    error_message = "geo_restriction.type must be none, whitelist or blacklist."
  }

  validation {
    condition     = (var.geo_restriction.type == "none") == (length(var.geo_restriction.locations) == 0) && alltrue([for c in var.geo_restriction.locations : can(regex("^[A-Z]{2}$", c))])
    error_message = "geo_restriction.locations must be upper-case country codes, empty only when type is none."
  }
}

variable "hsts" {
  type = object({
    max_age_sec        = optional(number, 63072000)
    include_subdomains = optional(bool, true)
    preload            = optional(bool, false)
  })
  default     = {}
  description = "Strict-Transport-Security of every response; preload stays off until the whole zone is HTTPS-only."

  validation {
    condition     = var.hsts.max_age_sec >= 31536000
    error_message = "hsts.max_age_sec must be at least one year."
  }
}

variable "log_bucket_arn" {
  type        = string
  default     = null
  description = "S3 bucket (log-archive account) of the access logs; null sends them to a CloudWatch log group in us-east-1 encrypted with kms_key_arn."

  validation {
    condition     = var.log_bucket_arn == null || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9.-]{3,63}$", var.log_bucket_arn))
    error_message = "log_bucket_arn must be an S3 bucket ARN."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "us-east-1 logs key that encrypts the CloudWatch log group of the access logs."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:us-east-1:", var.kms_key_arn))
    error_message = "kms_key_arn must be a key in us-east-1."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the CloudWatch log group of the access logs."
}

variable "log_record_fields" {
  type = list(string)
  default = [
    "date", "time", "x-edge-location", "x-edge-request-id", "x-host-header", "c-ip", "c-port", "x-forwarded-for",
    "cs-method", "cs-protocol", "cs-protocol-version", "cs(Host)", "cs-uri-stem", "cs-bytes", "cs(Referer)", "cs(User-Agent)",
    "sc-status", "sc-bytes", "sc-content-type", "sc-content-len", "time-taken", "time-to-first-byte",
    "x-edge-result-type", "x-edge-response-result-type", "x-edge-detailed-result-type", "ssl-protocol", "ssl-cipher",
  ]
  description = "Access log fields; the query string and cookies are left out because they can carry session tokens and client secrets."

  validation {
    condition     = length(setintersection(toset(var.log_record_fields), toset(["cs-uri-query", "cs(Cookie)"]))) == 0
    error_message = "log_record_fields must not contain cs-uri-query or cs(Cookie)."
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
