terraform {
  required_version = ">= 1.9"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }

  # Partial configuration: pass the bucket and key with -backend-config=backend.hcl (see backend.hcl.example).
  backend "s3" {}
}

# Authentication: a token (TF_VAR_github_token) when set, otherwise the GitHub App. Secrets come from the environment only.
provider "github" {
  owner = var.organization
  token = var.github_token

  dynamic "app_auth" {
    for_each = var.github_token == null ? [1] : []
    content {
      id              = var.github_app_id
      installation_id = var.github_app_installation_id
      pem_file        = var.github_app_pem
    }
  }
}
