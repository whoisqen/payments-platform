variable "name_prefix" {
  type        = string
  description = "Prefix of the secret name; set from config/platform.yaml (naming.prefix)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 11 lower-case letters or digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  default     = "shared-services"
  description = "Environment segment of the secret names; the admin tools run in the shared-services account."

  validation {
    condition     = var.environment == "shared-services"
    error_message = "the admin tools belong to the shared-services account."
  }
}

variable "okta_domain" {
  type        = string
  description = "Host of the Okta organization, for example acme.okta.com (config/platform.yaml, access.okta_domain)."

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.(okta|oktapreview|okta-emea)\\.com$", var.okta_domain))
    error_message = "okta_domain must be a host name of an Okta organization, without https://."
  }
}

variable "apps" {
  type = map(object({
    label                     = string
    redirect_uris             = list(string)
    post_logout_redirect_uris = optional(list(string), [])
    # PKCE is required unless the client cannot send a code challenge
    pkce_required = optional(bool, true)
  }))
  description = "Admin tools that sign in through Okta, by name (grafana, argocd, vault, proxy, sentry): each gets an OIDC application and the secret <prefix>/shared-services/<name>/oidc."

  validation {
    condition     = length(var.apps) > 0 && alltrue([for a in values(var.apps) : length(a.redirect_uris) > 0 && alltrue([for u in concat(a.redirect_uris, a.post_logout_redirect_uris) : can(regex("^(https://[^/]+|http://localhost:[0-9]+)/", u))])])
    error_message = "every application needs redirect URIs; each is https, or http://localhost for a command-line client."
  }

  validation {
    condition     = alltrue([for k in keys(var.apps) : can(regex("^[a-z][a-z0-9-]{1,30}$", k))])
    error_message = "application names are lower-case words, they become part of the secret name."
  }
}

variable "groups" {
  type        = map(string)
  description = "Okta group of each role (config/platform.yaml, access.grafana_groups); every admin tool maps the same six groups to its own roles: admin, sre, security, engineering, finance, audit."

  validation {
    condition     = toset(keys(var.groups)) == toset(["admin", "sre", "security", "engineering", "finance", "audit"])
    error_message = "groups must define exactly admin, sre, security, engineering, finance and audit."
  }

  validation {
    condition     = length(distinct(values(var.groups))) == length(var.groups)
    error_message = "two roles must not share a group."
  }
}

variable "admin_user_ids" {
  type        = list(string)
  default     = []
  description = "Okta user ids of the members of the administrator group (the owner and one reserve administrator). Members of the other groups are managed in Okta, not here."

  validation {
    condition     = length(var.admin_user_ids) == 0 || length(var.admin_user_ids) >= 2
    error_message = "name at least two administrators, or none (then the group is filled in Okta)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed key of the secrets (the shared key of the kms stack)."
}

variable "secret_recovery_window_days" {
  type        = number
  default     = 30
  description = "Days a deleted secret stays recoverable."
}

variable "tags" {
  type        = map(string)
  description = "Section 22 tags that Terragrunt default_tags do not set: team, owner, pci-scope, data-class, backup-tier."

  validation {
    condition     = alltrue([for k in ["team", "owner", "pci-scope", "data-class", "backup-tier"] : contains(keys(var.tags), k)])
    error_message = "tags must contain team, owner, pci-scope, data-class and backup-tier."
  }
}

variable "client_secret_rotation" {
  type        = map(string)
  default     = {}
  description = "Rotation id per application (for example the date of the rotation); a new id replaces the Okta application, which issues a new client id and secret into <prefix>/shared-services/<app>/oidc. The ExternalSecret refresh then restarts nothing by itself: roll the tool after the sync."

  validation {
    condition     = alltrue([for k in keys(var.client_secret_rotation) : contains(keys(var.apps), k)])
    error_message = "client_secret_rotation may name only applications of apps."
  }
}
