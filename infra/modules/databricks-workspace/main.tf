# Premium Azure Databricks workspace with VNet injection and secure cluster
# connectivity (no public IPs on cluster nodes), plus the Unity Catalog access
# connector and minimal diagnostic logs.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
  }
}

# The managed identity Unity Catalog uses to reach the lakehouse storage.
resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # ephemeral by design: destroyed nightly
resource "azurerm_databricks_workspace" "this" {
  #checkov:skip=CKV_AZURE_158:Front-end Private Link is a deliberate non-goal (design §4 option C): the lab must be demoable from a normal browser and reachable from GitHub-hosted runners. Front door is Entra ID + MFA.
  #checkov:skip=CKV2_AZURE_48:Customer-managed keys are out of scope (design §2).
  name                        = "dbw-${var.name_suffix}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  sku                         = "premium" # required: Unity Catalog, and Standard is no longer offered for new workspaces
  managed_resource_group_name = "rg-${var.name_suffix}-managed"

  # Front end stays public (Entra ID sign-in); see design §4.
  public_network_access_enabled = true
  # "AllRules" = no back-end Private Link; Databricks manages the NSG rules.
  network_security_group_rules_required = "AllRules"

  custom_parameters {
    no_public_ip        = true # secure cluster connectivity
    virtual_network_id  = var.vnet_id
    public_subnet_name  = var.host_subnet_name
    private_subnet_name = var.container_subnet_name

    public_subnet_network_security_group_association_id  = var.host_nsg_association_id
    private_subnet_network_security_group_association_id = var.container_nsg_association_id
  }

  tags = var.tags

  depends_on = [terraform_data.network_ready]
}

# Make sure NAT is attached to both subnets before the workspace exists.
resource "terraform_data" "network_ready" {
  input = var.network_ready_ids
}

# ---------------------------------------------------------------- diagnostics
# Keep categories minimal: the Log Analytics free 5 GB/month is shared across
# the billing account (design §11, item 5).

# tflint-ignore: azurerm_resources_missing_prevent_destroy # ephemeral by design: destroyed nightly
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "workspace" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_databricks_workspace.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_categories)
    content {
      category = enabled_log.value
    }
  }
}
