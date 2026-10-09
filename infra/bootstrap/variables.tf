variable "subscription_id" {
  description = "Subscription the lab lives in (Shanahan Enterprises Development). Kept out of git: set it in terraform.tfvars."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID. Kept out of git: set it in terraform.tfvars."
  type        = string
}

variable "location" {
  description = "Azure region for every lab resource."
  type        = string
  default     = "eastus2"
}

variable "location_short" {
  description = "Short region code used in names (CAF style)."
  type        = string
  default     = "eus2"
}

variable "github_owner" {
  description = "GitHub user or org that owns the lab repo."
  type        = string
  default     = "cjshanahan1228"
}

variable "github_repo" {
  description = "Lab repository name."
  type        = string
  default     = "azure-databricks-platform-lab"
}

variable "budget_amount" {
  description = "Monthly budget (USD) for the lab resource groups. Budgets alert; they don't stop spend."
  type        = number
  default     = 25
}

variable "budget_contact_emails" {
  description = "Who gets the budget alert emails."
  type        = list(string)

  validation {
    condition     = length(var.budget_contact_emails) > 0
    error_message = "Give at least one address for budget alerts."
  }
}

variable "apply_identity_subscription_contributor" {
  description = <<-EOT
    Phase 1 open question (design §7): can a resource-group-scoped Contributor
    create a VNet-injected workspace (Databricks creates the managed RG)? Leave
    false. Only set true if the first apply fails with an authorization error on
    the managed resource group, and record the result in the README.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags merged onto the defaults."
  type        = map(string)
  default     = {}
}
