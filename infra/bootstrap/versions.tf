terraform {
  required_version = ">= 1.9"

  # Bootstrap starts with LOCAL state (it creates the remote state account).
  # After the first apply, move it into that account. See README.md step 6.

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

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # The state account has shared keys disabled, so the provider must use
  # Entra ID for any data-plane call.
  storage_use_azuread = true

  # Colin runs this as an Owner of the subscription, so registering the
  # resource providers the lab needs happens here, once. The CI identities
  # can't register providers (and don't need to).
  resource_provider_registrations = "core"
  resource_providers_to_register = [
    "Microsoft.Consumption",
    "Microsoft.Databricks",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
  ]

  features {}
}
