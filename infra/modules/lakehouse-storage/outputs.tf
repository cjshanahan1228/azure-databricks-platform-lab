output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "container_name" {
  value = azurerm_storage_container.lakehouse.name
}

output "abfss_url" {
  description = "Root of the lakehouse container, for the Unity Catalog external location."
  value       = "abfss://${azurerm_storage_container.lakehouse.name}@${azurerm_storage_account.this.primary_dfs_host}/"
}

# The UC storage credential must not be created until the role assignment
# and private endpoints exist, or validation fails.
output "ready_ids" {
  value = concat(
    [azurerm_role_assignment.access_connector_blob.id],
    [for p in azurerm_private_endpoint.this : p.id],
  )
}
