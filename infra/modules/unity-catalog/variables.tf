variable "prefix" {
  description = "Name prefix for UC objects (unique per metastore)."
  type        = string
  default     = "dbxlab"
}

variable "name_suffix" {
  description = "Per-deploy suffix for the storage credential and external location names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,8}$", var.name_suffix))
    error_message = "name_suffix must be 4-8 lowercase letters/digits."
  }
}

variable "access_connector_id" {
  type = string
}

variable "lakehouse_url" {
  description = "abfss:// URL of the lakehouse container root, with a trailing slash."
  type        = string

  validation {
    condition     = startswith(var.lakehouse_url, "abfss://") && endswith(var.lakehouse_url, "/")
    error_message = "lakehouse_url must look like abfss://<container>@<account>.dfs.core.windows.net/"
  }
}

variable "catalog_name" {
  type    = string
  default = "dbxlab"
}

variable "schemas" {
  type    = list(string)
  default = ["bronze", "silver", "gold"]
}

variable "lab_admin" {
  description = "User (email/UPN) or group that gets full rights on the lab catalog."
  type        = string
}
