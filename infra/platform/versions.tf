terraform {
  required_version = ">= 1.9"

  # Partial config: resource_group_name / storage_account_name / container_name
  # come from -backend-config (CI: repo variables; locally: backend.hcl).
  # Auth is Entra ID only: the state account has shared keys disabled.
  backend "azurerm" {
    key              = "platform.tfstate"
    use_azuread_auth = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Credentials come from the environment: in CI, ARM_USE_OIDC + ARM_CLIENT_ID +
# ARM_TENANT_ID + ARM_SUBSCRIPTION_ID (GitHub OIDC -> managed identity);
# locally, `az login`.
provider "azurerm" {
  subscription_id = var.subscription_id

  # Shared keys are off on every storage account.
  storage_use_azuread = true

  # The CI identities can't (and needn't) register resource providers;
  # bootstrap did that once.
  resource_provider_registrations = "none"

  features {
    storage {
      # Don't make data-plane calls to storage accounts. The lakehouse account
      # has public network access disabled, and GitHub-hosted runners aren't
      # in the VNet, so data-plane reads would fail during plan.
      data_plane_available = false
    }

    resource_group {
      # The lab RG is owned by bootstrap; never delete it from here.
      prevent_deletion_if_contains_resources = true
    }
  }
}
