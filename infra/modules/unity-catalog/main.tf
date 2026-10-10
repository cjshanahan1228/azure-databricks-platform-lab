# Unity Catalog objects for the lab, created INSIDE the account-level metastore
# that already exists for East US 2 (the metastore itself is never managed
# here: it is long-lived and shared by every workspace in the region).
#
#   storage credential  -> access connector managed identity
#   external location   -> abfss://lakehouse@<account>/
#   catalog dbxlab      -> managed storage under that location
#   schemas             -> bronze, silver, gold
#   grants              -> the lab admin (Colin)
#
# Naming: the storage credential and external location carry a per-deploy
# suffix (var.name_suffix), so a leftover from a failed destroy can't collide
# by name with the next deploy (names are unique per metastore). Their URL
# can't collide either, because the lakehouse storage account name is new on
# every deploy. The CATALOG keeps the stable name `dbxlab`, because phase 2
# code refers to `dbxlab.<layer>.<table>`; an orphaned `dbxlab` catalog
# therefore DOES block the next deploy. deploy.yml checks for that before
# applying and points to docs/runbooks/orphaned-unity-catalog-objects.md.
#
# Everything has force_destroy = true because the lab is ephemeral. Destroy
# order (Terraform reverse dependencies): grants -> schemas -> catalog ->
# external location -> storage credential, and destroy.yml runs this stack
# BEFORE the platform stack removes the workspace.

terraform {
  required_version = ">= 1.9"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.137"
    }
  }
}

resource "databricks_storage_credential" "this" {
  name    = "${var.prefix}-access-connector-${var.name_suffix}"
  comment = "Lab: access connector managed identity for the lakehouse account. Managed by Terraform."

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }

  force_destroy = true
}

resource "databricks_external_location" "lakehouse" {
  name            = "${var.prefix}-lakehouse-${var.name_suffix}"
  url             = var.lakehouse_url
  credential_name = databricks_storage_credential.this.name
  comment         = "Lab lakehouse container. Managed by Terraform."
  force_destroy   = true
}

resource "databricks_catalog" "this" {
  name         = var.catalog_name
  comment      = "Personal lab catalog (public data only). Ephemeral; managed by Terraform."
  storage_root = "${var.lakehouse_url}${var.catalog_name}"

  properties = {
    purpose = "databricks-platform-lab"
  }

  force_destroy = true

  depends_on = [databricks_external_location.lakehouse]
}

resource "databricks_schema" "layers" {
  for_each = toset(var.schemas)

  catalog_name  = databricks_catalog.this.name
  name          = each.value
  comment       = "Medallion layer: ${each.value}."
  force_destroy = true
}

# databricks_grants is AUTHORITATIVE for each securable: anything granted by
# hand in the UI will be removed on the next apply. Do hand experiments in
# your own catalog, not this one.

resource "databricks_grants" "catalog" {
  catalog = databricks_catalog.this.name

  grant {
    principal  = var.lab_admin
    privileges = ["ALL_PRIVILEGES"]
  }
}

resource "databricks_grants" "external_location" {
  external_location = databricks_external_location.lakehouse.id

  grant {
    principal  = var.lab_admin
    privileges = ["READ_FILES", "WRITE_FILES", "CREATE_EXTERNAL_TABLE", "CREATE_EXTERNAL_VOLUME"]
  }
}

resource "databricks_grants" "storage_credential" {
  storage_credential = databricks_storage_credential.this.id

  grant {
    principal  = var.lab_admin
    privileges = ["CREATE_EXTERNAL_LOCATION"]
  }
}
