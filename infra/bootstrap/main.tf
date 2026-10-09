# Bootstrap: the persistent, rarely-changing foundation. Colin applies this
# locally ONCE with his own `az login` (CI can't create its own identity).
#
# Creates:
#   rg-dbxlab-state   state storage account (Entra-only), budget lives on the subscription
#   rg-dbxlab-eus2    the EMPTY lab resource group; platform/workspace fill and empty it
#   id-gh-dbxlab-plan / id-gh-dbxlab-apply  + GitHub federated credentials
#   least-privilege role assignments, and the $25/month budget.

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {
  subscription_id = var.subscription_id
}

locals {
  name_suffix = "dbxlab-${var.location_short}"
  repo        = "${var.github_owner}/${var.github_repo}"

  tags = merge({
    project    = "databricks-platform-lab"
    owner      = "colin"
    env        = "lab"
    lifecycle  = "persistent"
    managed_by = "terraform"
    repo       = var.github_repo
  }, var.tags)

  lab_rg_name     = "rg-${local.name_suffix}"
  managed_rg_name = "rg-${local.name_suffix}-managed"

  # Built-in role definition IDs (same in every tenant).
  role_storage_blob_data_contributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  role_cognitive_services_openai_usr = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
}

resource "random_string" "state_suffix" {
  length  = 4
  upper   = false
  special = false
}

# ---------------------------------------------------------------- resource groups

resource "azurerm_resource_group" "state" {
  name     = "rg-dbxlab-state"
  location = var.location
  tags     = local.tags
}

# Persistent but EMPTY. The ephemeral stacks create and destroy everything
# inside it, so the apply identity's RG-scoped roles and the budget filter
# survive every destroy.
resource "azurerm_resource_group" "lab" {
  name     = local.lab_rg_name
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- state account

resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_59:State must be reachable from GitHub-hosted runners (dynamic IPs). Entra-only auth (shared keys off) is the control instead.
  #checkov:skip=CKV_AZURE_33:Queue service is unused; there is nothing to log.
  #checkov:skip=CKV_AZURE_206:LRS is deliberate for a lab; versioning + soft delete cover accidental overwrites. GRS would double the (tiny) cost for no lab benefit.
  #checkov:skip=CKV2_AZURE_1:Customer-managed keys are out of scope (design §2); Microsoft-managed keys + infrastructure encryption.
  #checkov:skip=CKV2_AZURE_33:No private endpoint: GitHub-hosted runners can't reach one.
  #checkov:skip=CKV2_AZURE_21:Blob read logging to Log Analytics would cost more than the account; access is Entra-only and audited in the activity log.
  name                = "stdbxlabtf${random_string.state_suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  # Entra ID only.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false
  sftp_enabled                    = false

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  public_network_access             = "Enabled"

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  sas_policy {
    expiration_period = "00.01:00:00"
  }

  tags = local.tags

  lifecycle {
    # Holds every stack's state. Remove deliberately, never by accident.
    prevent_destroy = true
  }
}

# Created through the ARM management plane (storage_account_id), so no
# data-plane access is needed to create it.
resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:See the storage account.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

# Colin (whoever runs bootstrap) needs data-plane access to read and write
# state blobs. Owner on the subscription does NOT include blob data actions.
resource "azurerm_role_assignment" "runner_state_blob" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Bootstrap operator: read/write Terraform state with Entra ID."
}

# ---------------------------------------------------------------- CI identities

resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-gh-dbxlab-plan"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "apply" {
  name                = "id-gh-dbxlab-apply"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = local.tags
}

locals {
  github_issuer   = "https://token.actions.githubusercontent.com"
  github_audience = ["api://AzureADTokenExchange"]

  # Design §7, "Federated credentials needed". The lab-demo (phase 5) subject
  # is intentionally NOT created yet.
  federated_credentials = {
    plan-pull-request = {
      identity = azurerm_user_assigned_identity.plan.id
      subject  = "repo:${local.repo}:pull_request"
    }
    plan-main = {
      identity = azurerm_user_assigned_identity.plan.id
      subject  = "repo:${local.repo}:ref:refs/heads/main"
    }
    apply-env-lab = {
      identity = azurerm_user_assigned_identity.apply.id
      subject  = "repo:${local.repo}:environment:lab"
    }
    apply-env-lab-destroy = {
      identity = azurerm_user_assigned_identity.apply.id
      subject  = "repo:${local.repo}:environment:lab-destroy"
    }
  }
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_credentials

  name                      = "github-${each.key}"
  user_assigned_identity_id = each.value.identity
  issuer                    = local.github_issuer
  audience                  = local.github_audience
  subject                   = each.value.subject
}

# ---------------------------------------------------------------- role assignments
# Plan identity: read the lab, and lock state (a blob lease is a write).

resource "azurerm_role_assignment" "plan_reader_lab" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI plan: read lab resources for refresh."
}

resource "azurerm_role_assignment" "plan_state_blob" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI plan: read state and take the state lock (blob lease)."
}

# Apply identity: build and destroy everything inside the lab RG.

resource "azurerm_role_assignment" "apply_contributor_lab" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI apply/destroy: manage lab resources. Also makes it a Databricks workspace admin."
}

# Fallback for design §7's open question. Off by default.
resource "azurerm_role_assignment" "apply_contributor_subscription" {
  count = var.apply_identity_subscription_contributor ? 1 : 0

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
  description          = "Fallback: subscription Contributor because RG-scoped Contributor couldn't create the Databricks managed RG."
}

resource "azurerm_role_assignment" "apply_state_blob" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI apply/destroy: read and write state."
}

# The access connector needs Storage Blob Data Contributor on the lakehouse
# account (phase 3 adds Cognitive Services OpenAI User), so the apply identity
# must be able to create role assignments. This ABAC condition limits it to
# assigning or deleting ONLY those two roles, so it can't make anything Owner.
resource "azurerm_role_assignment" "apply_rbac_admin_conditioned" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
  principal_type       = "ServicePrincipal"
  description          = "CI apply: may only assign/remove Storage Blob Data Contributor and Cognitive Services OpenAI User inside the lab RG."

  condition_version = "2.0"
  condition         = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_storage_blob_data_contributor}, ${local.role_cognitive_services_openai_usr}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_storage_blob_data_contributor}, ${local.role_cognitive_services_openai_usr}}
     )
    )
  EOT
}

# ---------------------------------------------------------------- budget
# Subscription budget FILTERED to the lab RGs. Cluster VMs bill into the
# Databricks-managed RG, so a budget scoped only to rg-dbxlab-eus2 would miss
# most of the compute cost. The managed RG doesn't exist yet; filtering on its
# name works anyway.

resource "azurerm_consumption_budget_subscription" "lab" {
  name            = "budget-dbxlab-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  filter {
    dimension {
      name     = "ResourceGroupName"
      operator = "In"
      values = [
        azurerm_resource_group.lab.name,
        local.managed_rg_name,
        azurerm_resource_group.state.name,
      ]
    }
  }

  dynamic "notification" {
    for_each = {
      actual-50    = { threshold = 50, type = "Actual" }
      actual-80    = { threshold = 80, type = "Actual" }
      actual-100   = { threshold = 100, type = "Actual" }
      forecast-100 = { threshold = 100, type = "Forecasted" }
    }

    content {
      enabled        = true
      threshold      = notification.value.threshold
      threshold_type = notification.value.type
      operator       = "GreaterThanOrEqualTo"
      contact_emails = var.budget_contact_emails
    }
  }

  lifecycle {
    # The start date is fixed at creation; don't churn it every month.
    ignore_changes = [time_period]
  }
}
