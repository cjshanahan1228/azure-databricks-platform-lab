# The first four come from `terraform output` of the platform stack
# (deploy.yml writes them to platform.auto.tfvars.json).

variable "workspace_url" {
  type = string
}

variable "workspace_resource_id" {
  type = string
}

variable "access_connector_id" {
  type = string
}

variable "lakehouse_url" {
  type = string
}

variable "lab_admin" {
  description = "Colin's Databricks user (Entra UPN/email). Set via TF_VAR_lab_admin from the LAB_ADMIN repo variable."
  type        = string
}

variable "allowed_node_types" {
  description = "Node sizes the cluster policy allows (design §9: DS3_v2 low end, D4ds_v5 high end)."
  type        = list(string)
  default     = ["Standard_DS3_v2", "Standard_D4ds_v5"]
}

variable "autotermination_minutes" {
  type    = number
  default = 15
}
