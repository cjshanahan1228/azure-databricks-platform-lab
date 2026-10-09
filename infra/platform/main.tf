# Platform stack (ephemeral): everything Azure-side that the lab needs.
# Applied by deploy.yml, destroyed nightly by destroy.yml (after the workspace
# stack). The RG itself belongs to bootstrap and is never deleted here.

data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

locals {
  name_suffix = "dbxlab-${var.location_short}"

  tags = merge({
    project    = "databricks-platform-lab"
    owner      = "colin"
    env        = "lab"
    lifecycle  = "ephemeral"
    managed_by = "terraform"
    repo       = "azure-databricks-platform-lab"
  }, var.tags)
}

module "network" {
  source = "../modules/network"

  name_suffix         = local.name_suffix
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = var.location
  address_space       = var.address_space
  tags                = local.tags
}

module "workspace" {
  source = "../modules/databricks-workspace"

  name_suffix         = local.name_suffix
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = var.location

  vnet_id                      = module.network.vnet_id
  host_subnet_name             = module.network.host_subnet_name
  container_subnet_name        = module.network.container_subnet_name
  host_nsg_association_id      = module.network.host_nsg_association_id
  container_nsg_association_id = module.network.container_nsg_association_id
  network_ready_ids            = module.network.nat_association_ids

  tags = local.tags
}

module "lakehouse_storage" {
  source = "../modules/lakehouse-storage"

  name_suffix         = local.name_suffix
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = var.location

  vnet_id                       = module.network.vnet_id
  pep_subnet_id                 = module.network.pep_subnet_id
  access_connector_id           = module.workspace.access_connector_id
  access_connector_principal_id = module.workspace.access_connector_principal_id

  tags = local.tags
}
