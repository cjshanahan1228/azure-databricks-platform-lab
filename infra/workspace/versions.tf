terraform {
  required_version = ">= 1.9"

  backend "azurerm" {
    key              = "workspace.tfstate"
    use_azuread_auth = true
  }

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.137"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# A separate root from `platform` on purpose: this provider is configured
# from the workspace that `platform` creates. Configuring a provider from a
# resource in the same state breaks plans before the workspace exists and
# destroys in the wrong order (design §6).
#
# Auth comes from the environment:
#   CI:     DATABRICKS_AUTH_TYPE=github-oidc-azure, ARM_CLIENT_ID, ARM_TENANT_ID
#           (the apply identity is a workspace admin because it is Contributor
#           on the workspace resource)
#   local:  DATABRICKS_AUTH_TYPE=azure-cli after `az login`
provider "databricks" {
  host                        = var.workspace_url
  azure_workspace_resource_id = var.workspace_resource_id
}
