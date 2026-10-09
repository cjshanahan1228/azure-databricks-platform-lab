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
  type = string
}

variable "host_subnet_name" {
  type = string
}

variable "container_subnet_name" {
  type = string
}

variable "host_nsg_association_id" {
  type = string
}

variable "container_nsg_association_id" {
  type = string
}

variable "network_ready_ids" {
  description = "IDs the workspace must wait for (NAT associations)."
  type        = list(string)
  default     = []
}

variable "diagnostic_categories" {
  description = "Databricks diagnostic log categories sent to Log Analytics. Keep this short."
  type        = list(string)
  default     = ["accounts", "clusters", "jobs", "unityCatalog"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
