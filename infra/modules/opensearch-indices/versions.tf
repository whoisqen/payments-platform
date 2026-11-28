terraform {
  required_version = ">= 1.9"

  required_providers {
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = ">= 2.3, < 3.0"
    }
  }
}
