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

# The key is passed as TF_VAR_github_app_pem from the environment; it is never stored in the repository.
provider "github" {
  owner = var.organization

  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = var.github_app_pem
  }
}
