# ADLS Gen2 for the lakehouse: firewalled to the access connector, no shared keys,
# reached by clusters through private endpoints (dfs + blob) and by Unity
# Catalog through the access connector's managed identity.

terraform {
  required_version = ">= 1.9"

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

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

# tflint-ignore: azurerm_resources_missing_prevent_destroy # ephemeral by design: destroyed nightly
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_206:LRS is deliberate: ephemeral lab holding a re-downloadable public dataset.
  #checkov:skip=CKV2_AZURE_1:Customer-managed keys are out of scope (design §2).
  #checkov:skip=CKV2_AZURE_21:Storage read logging would cost more than the lab's data; UC audit logs cover data access.
  #checkov:skip=CKV_AZURE_33:Queue service is unused.
  #checkov:skip=CKV_AZURE_59:Public endpoint is "Enabled from selected networks" only: default_action Deny, no IP/VNet rules, no trusted-services bypass; the single resource-instance rule admits the lab's access connector (Unity Catalog). Clusters use private endpoints.
  #checkov:skip=CKV_AZURE_36:Deliberate: no blanket trusted-services bypass. Only the lab's access connector is allowed, via a resource-instance rule (Databricks' recommended pattern).
  name                = "stdbxlab${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
  is_hns_enabled           = true # ADLS Gen2 (hierarchical namespace)

  # Entra ID only.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false
  sftp_enabled                    = false

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  # Firewalled to the access connector (Databricks' documented "standard
  # approach" for UC with a storage firewall): the public endpoint is enabled
  # only for selected networks, the default action is Deny, there are no IP
  # or VNet rules and no trusted-services bypass, and one resource-instance
  # rule admits the lab's access connector so the Unity Catalog control plane
  # can validate the credential/location and vend credentials. Clusters
  # (compute plane) reach the account through the private endpoints below.
  public_network_access = "Enabled"

  network_rules {
    default_action = "Deny"
    bypass         = ["None"] # no blanket "trusted Azure services" exception

    private_link_access {
      endpoint_resource_id = var.access_connector_id
    }
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "00.01:00:00"
  }

  tags = var.tags
}

# Through the ARM management plane, so the GitHub runner never needs
# data-plane network access to a firewalled account.
# tflint-ignore: azurerm_resources_missing_prevent_destroy # ephemeral by design: destroyed nightly
resource "azurerm_storage_container" "lakehouse" {
  #checkov:skip=CKV2_AZURE_21:Storage read logging would cost more than the lab's data; UC audit logs cover data access.
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Unity Catalog's identity for this storage. The apply identity can create this
# assignment only because of its ABAC-conditioned RBAC Administrator role.
resource "azurerm_role_assignment" "access_connector_blob" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.access_connector_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Unity Catalog storage credential (access connector) to the lakehouse account."
}

# ---------------------------------------------------------------- private DNS + endpoints

locals {
  endpoints = {
    dfs  = "privatelink.dfs.core.windows.net"  # required: ABFS / Unity Catalog
    blob = "privatelink.blob.core.windows.net" # recommended: blob APIs
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.endpoints

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.endpoints

  name                 = "link-${each.key}-${var.name_suffix}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.endpoints

  name                          = "pep-st-${each.key}-dbxlab"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.pep_subnet_id
  custom_network_interface_name = "nic-pep-st-${each.key}-dbxlab"

  private_service_connection {
    name                           = "psc-st-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.key].id]
  }

  tags = var.tags
}
