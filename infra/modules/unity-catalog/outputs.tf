output "catalog_name" {
  value = databricks_catalog.this.name
}

output "external_location_name" {
  value = databricks_external_location.lakehouse.name
}

output "storage_credential_name" {
  value = databricks_storage_credential.this.name
}

output "schemas" {
  value = [for s in databricks_schema.layers : s.id]
}
