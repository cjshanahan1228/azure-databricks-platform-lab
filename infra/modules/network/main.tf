# VNet for Databricks VNet injection + private endpoints, NSGs, and NAT egress.
#
#   snet-dbx-host       ("public" subnet in Databricks terms; no public IPs with SCC)
#   snet-dbx-container  ("private" subnet)
#   snet-pep            private endpoints for the lakehouse storage
#
# Both Databricks subnets are delegated to Microsoft.Databricks/workspaces and
# must each have an NSG associated. Databricks adds the rules it needs to those
# NSGs itself (network_security_group_rules_required = "AllRules"), so this
# module creates them EMPTY and doesn't manage their rules.

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
  }
}

locals {
  dbx_subnets = {
    host      = { name = "snet-dbx-host", prefix = var.host_subnet_prefix }
    container = { name = "snet-dbx-container", prefix = var.container_subnet_prefix }
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_network_security_group" "dbx" {
  for_each = local.dbx_subnets

  name                = "nsg-dbx-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet" "dbx" {
  for_each = local.dbx_subnets

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]

  # Private subnet: no implicit internet egress. All outbound goes via NAT.
  default_outbound_access_enabled = false

  delegation {
    name = "databricks"

    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "dbx" {
  for_each = local.dbx_subnets

  subnet_id                 = azurerm_subnet.dbx[each.key].id
  network_security_group_id = azurerm_network_security_group.dbx[each.key].id
}

# Private endpoints only. No delegation, no NSG needed for PEs (network
# policies left at the default, which is Disabled for PEs).
resource "azurerm_subnet" "pep" {
  #checkov:skip=CKV2_AZURE_31:Subnet holds only private endpoints; NSG rules don't apply to PE traffic with network policies disabled.
  name                            = "snet-pep"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.pep_subnet_prefix]
  default_outbound_access_enabled = false
}

# ---------------------------------------------------------------- NAT egress
# Required, not optional: with secure cluster connectivity the nodes have no
# public IPs, and new subnets have no default outbound access.

resource "azurerm_public_ip" "nat" {
  name                = "pip-ng-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "ng-${var.name_suffix}"
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "dbx" {
  for_each = local.dbx_subnets

  subnet_id      = azurerm_subnet.dbx[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
