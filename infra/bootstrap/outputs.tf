output "state_resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "state_container_name" {
  value = azurerm_storage_container.tfstate.name
}

output "lab_resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "plan_client_id" {
  description = "AZURE_CLIENT_ID_PLAN repo variable."
  value       = azurerm_user_assigned_identity.plan.client_id
}

output "apply_client_id" {
  description = "AZURE_CLIENT_ID_APPLY repo variable."
  value       = azurerm_user_assigned_identity.apply.client_id
}

output "apply_principal_name" {
  description = "Display name to search for in the Databricks account console when granting metastore privileges."
  value       = azurerm_user_assigned_identity.apply.name
}

output "github_variables_commands" {
  description = "Run these from the repo root (review first). They set repository VARIABLES, not secrets: identifiers only."
  value       = <<-EOT
    gh variable set AZURE_TENANT_ID        --repo ${local.repo} --body '${var.tenant_id}'
    gh variable set AZURE_SUBSCRIPTION_ID  --repo ${local.repo} --body '${var.subscription_id}'
    gh variable set AZURE_CLIENT_ID_PLAN   --repo ${local.repo} --body '${azurerm_user_assigned_identity.plan.client_id}'
    gh variable set AZURE_CLIENT_ID_APPLY  --repo ${local.repo} --body '${azurerm_user_assigned_identity.apply.client_id}'
    gh variable set TFSTATE_STORAGE_ACCOUNT --repo ${local.repo} --body '${azurerm_storage_account.state.name}'
  EOT
}
