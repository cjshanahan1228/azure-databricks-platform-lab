variable "subscription_id" {
  description = "Set via TF_VAR_subscription_id (CI: from the AZURE_SUBSCRIPTION_ID repo variable). Never committed."
  type        = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "location_short" {
  type    = string
  default = "eus2"
}

variable "resource_group_name" {
  description = "The persistent, empty lab RG created by bootstrap."
  type        = string
  default     = "rg-dbxlab-eus2"
}

variable "address_space" {
  description = "VNet CIDR. Confirm it doesn't overlap anything you peer or VPN into."
  type        = string
  default     = "10.60.0.0/23"
}

variable "tags" {
  type    = map(string)
  default = {}
}
