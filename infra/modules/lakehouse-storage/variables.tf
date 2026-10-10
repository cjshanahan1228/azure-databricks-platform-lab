variable "name_suffix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_id" {
  description = "VNet the private DNS zones are linked to."
  type        = string
}

variable "pep_subnet_id" {
  type = string
}

variable "access_connector_id" {
  description = "Resource ID of the Databricks access connector (resource-instance network rule)."
  type        = string
}

variable "access_connector_principal_id" {
  description = "Object ID of the access connector's system-assigned identity."
  type        = string
}

variable "container_name" {
  type    = string
  default = "lakehouse"
}

variable "tags" {
  type    = map(string)
  default = {}
}
