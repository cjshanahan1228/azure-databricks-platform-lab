output "metastore_id" {
  description = "Metastore the workspace is attached to (sanity check)."
  value       = data.databricks_current_metastore.this.id
}

output "catalog_name" {
  value = module.unity_catalog.catalog_name
}

output "cluster_policy_id" {
  value = databricks_cluster_policy.single_node_lab.id
}
