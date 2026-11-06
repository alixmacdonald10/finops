# OpenTofu version and provider constraints (providers pinned to registry.opentofu.org) and azurerm provider config.

terraform {
  required_version = ">= 1.7.0"

  # No backend block = local state (terraform.tfstate in this directory).
  required_providers {
    azurerm = {
      source  = "registry.opentofu.org/hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "registry.opentofu.org/hashicorp/random"
      version = "~> 3.6"
    }
    http = {
      source  = "registry.opentofu.org/hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {}

  # Auth via `az login`. Subscription from var or ARM_SUBSCRIPTION_ID env var.
  subscription_id = var.subscription_id
}
