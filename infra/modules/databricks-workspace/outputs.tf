output "workspace_id" {
  description = "Azure resource ID of the workspace."
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  description = "Workspace URL (changes on every deploy)."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "workspace_numeric_id" {
  value = azurerm_databricks_workspace.this.workspace_id
}

output "managed_resource_group_name" {
  value = azurerm_databricks_workspace.this.managed_resource_group_name
}

output "access_connector_id" {
  value = azurerm_databricks_access_connector.this.id
}

output "access_connector_principal_id" {
  value = azurerm_databricks_access_connector.this.identity[0].principal_id
}
