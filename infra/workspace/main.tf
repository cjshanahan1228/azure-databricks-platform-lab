# Workspace stack (ephemeral): Unity Catalog objects and the cluster policy.
# Applied after `platform`, destroyed BEFORE it.

# Fails fast with a clear error if the new workspace isn't attached to a
# metastore (fix: turn on auto-assignment for the East US 2 metastore in the
# account console; see docs/learning/phase-1.md).
data "databricks_current_metastore" "this" {}

module "unity_catalog" {
  source = "../modules/unity-catalog"

  access_connector_id = var.access_connector_id
  lakehouse_url       = var.lakehouse_url
  lab_admin           = var.lab_admin
}

# ---------------------------------------------------------------- cluster policy
# Guardrail from design §11. Written in JSON so it reads exactly like the
# cluster JSON you see in the UI ("Compute > your cluster > ... > View JSON").

resource "databricks_cluster_policy" "single_node_lab" {
  name                  = "lab-single-node"
  description           = "Single node, ${var.autotermination_minutes}-minute auto-termination, small VMs, lab tags. Managed by Terraform."
  max_clusters_per_user = 1

  definition = templatefile("${path.module}/policies/single-node-lab.json.tftpl", {
    node_types              = jsonencode(var.allowed_node_types)
    default_node_type       = jsonencode(var.allowed_node_types[0])
    autotermination_minutes = var.autotermination_minutes
  })
}

resource "databricks_permissions" "policy_use" {
  cluster_policy_id = databricks_cluster_policy.single_node_lab.id

  access_control {
    user_name        = var.lab_admin
    permission_level = "CAN_USE"
  }
}
