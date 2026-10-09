# The workspace stack reads these (deploy.yml / destroy.yml pass them in as
# TF_VAR_* values). None of them are secrets, but the workspace URL and
# resource ID are never echoed in public workflow logs.

output "workspace_resource_id" {
  value = module.workspace.workspace_id
}

output "workspace_url" {
  value = module.workspace.workspace_url
}

output "managed_resource_group_name" {
  value = module.workspace.managed_resource_group_name
}

output "access_connector_id" {
  value = module.workspace.access_connector_id
}

output "lakehouse_storage_account_name" {
  value = module.lakehouse_storage.storage_account_name
}

output "lakehouse_url" {
  value = module.lakehouse_storage.abfss_url
}

output "nat_public_ip" {
  value = module.network.nat_public_ip
}

output "uc_ready_ids" {
  description = "Role assignment + private endpoints that must exist before UC objects are created."
  value       = module.lakehouse_storage.ready_ids
}
