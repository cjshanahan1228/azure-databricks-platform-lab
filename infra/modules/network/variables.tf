variable "name_suffix" {
  description = "e.g. dbxlab-eus2"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "VNet CIDR. Confirm it doesn't overlap anything you peer or VPN into."
  type        = string
  default     = "10.60.0.0/23"
}

variable "host_subnet_prefix" {
  description = "Databricks host (public) subnet. Databricks needs at least /26."
  type        = string
  default     = "10.60.0.0/25"
}

variable "container_subnet_prefix" {
  description = "Databricks container (private) subnet. Databricks needs at least /26."
  type        = string
  default     = "10.60.0.128/25"
}

variable "pep_subnet_prefix" {
  description = "Private endpoint subnet."
  type        = string
  default     = "10.60.1.0/27"
}

variable "tags" {
  type    = map(string)
  default = {}
}
