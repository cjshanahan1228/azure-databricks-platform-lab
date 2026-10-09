output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "host_subnet_name" {
  value = azurerm_subnet.dbx["host"].name
}

output "container_subnet_name" {
  value = azurerm_subnet.dbx["container"].name
}

output "host_nsg_association_id" {
  value = azurerm_subnet_network_security_group_association.dbx["host"].id
}

output "container_nsg_association_id" {
  value = azurerm_subnet_network_security_group_association.dbx["container"].id
}

output "pep_subnet_id" {
  value = azurerm_subnet.pep.id
}

output "nat_public_ip" {
  description = "The single egress IP for cluster traffic."
  value       = azurerm_public_ip.nat.ip_address
}

# Exposed so the workspace can depend on NAT being attached before it is
# created (otherwise the first cluster may start with no egress).
output "nat_association_ids" {
  value = [for a in azurerm_subnet_nat_gateway_association.dbx : a.id]
}
