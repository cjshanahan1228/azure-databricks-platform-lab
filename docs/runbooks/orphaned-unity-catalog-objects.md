# Runbook: orphaned Unity Catalog objects

**Symptom.** Deploy fails at *Workspace stack* with "Orphaned Unity Catalog
objects: catalog 'dbxlab' already exists in the metastore but isn't in
Terraform state", or `terraform apply` on `infra/workspace` fails with
`already exists`.

**Cause.** Unity Catalog objects live in the **account-level metastore**, not
in the workspace. If the workspace (platform stack) went away without the
workspace stack being destroyed first (a failed or interrupted destroy, a
manual portal delete, or state loss), the objects outlive it:

| Object | Name | Blocks the next deploy? |
|---|---|---|
| Catalog | `dbxlab` (stable on purpose: phase 2 code uses `dbxlab.<layer>.<table>`) | **Yes**, same name |
| External location | `dbxlab-lakehouse-<suffix>` | No: the suffix and the storage account name are new on every deploy. Still clutter, and it points at a storage account that no longer exists. |
| Storage credential | `dbxlab-access-connector-<suffix>` | No (same reason). Points at a deleted access connector. |

Orphans cost nothing, but leave them and they accumulate.

## 1. Get a workspace attached to the metastore

The commands need *a* workspace in East US 2 attached to the metastore. Any
workspace works because the objects are metastore-level. If the lab is down:
run **Deploy** with `DEPLOY_WORKSPACE_STACK` unset or `false` (platform only),
approve it, and use that workspace. Destroy again afterwards.

Sign in as yourself (you're metastore admin) with the Databricks CLI:

```sh
az login --tenant <tenant-id>
export DATABRICKS_HOST="https://<workspace-host>"   # portal: dbw-dbxlab-eus2 > URL
export DATABRICKS_AUTH_TYPE=azure-cli
databricks current-user me --output json | jq -r .userName   # sanity check
```

## 2. Detect

```sh
databricks catalogs list --output json \
  | jq -r '.[] | select(.name == "dbxlab") | "\(.name)  owner=\(.owner)  root=\(.storage_root)"'

databricks external-locations list --output json \
  | jq -r '.[] | select(.name | startswith("dbxlab-")) | "\(.name)  \(.url)  cred=\(.credential_name)"'

databricks storage-credentials list --output json \
  | jq -r '.[] | select(.name | startswith("dbxlab-")) | .name'
```

Anything listed that isn't in the current workspace state
(`terraform -chdir=infra/workspace state list`) is an orphan. With the lab
destroyed, *everything* listed is an orphan.

## 3. Remove, in this order

Dependants first: catalog, then external locations, then credentials.
`--force` deletes even if the catalog still has schemas/tables, or the
location/credential is still referenced. The underlying storage is already
gone, so there's no data to keep.

```sh
databricks catalogs delete dbxlab --force

for loc in $(databricks external-locations list --output json | jq -r '.[] | select(.name | startswith("dbxlab-")) | .name'); do
  databricks external-locations delete "$loc" --force
done

for cred in $(databricks storage-credentials list --output json | jq -r '.[] | select(.name | startswith("dbxlab-")) | .name'); do
  databricks storage-credentials delete "$cred" --force
done
```

REST equivalents (same auth, `Authorization: Bearer $(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv)`):

```
DELETE $DATABRICKS_HOST/api/2.1/unity-catalog/catalogs/dbxlab?force=true
DELETE $DATABRICKS_HOST/api/2.1/unity-catalog/external-locations/<name>?force=true
DELETE $DATABRICKS_HOST/api/2.1/unity-catalog/storage-credentials/<name>?force=true
```

## 4. Reset Terraform state if needed

If `infra/workspace` state still lists objects that no longer exist (the
destroy died halfway), drop them so the next destroy/apply doesn't try to read
them through a dead workspace:

```sh
cd infra/workspace
terraform init -backend-config=backend.hcl
terraform state list
terraform state rm module.unity_catalog databricks_cluster_policy.single_node_lab databricks_permissions.policy_use random_string.uc_suffix
```

Then re-run **Deploy**.

## Why the catalog name isn't suffixed

Suffixing the catalog would make orphans harmless, but every notebook, job and
query in phase 2+ would need the suffix injected. A stable `dbxlab` plus the
pre-apply check in `deploy.yml` (fails fast and points here) is the trade-off:
normal destroys remove it (workspace stack destroyed *before* platform, with
`force_destroy = true`), and only an abnormal teardown needs this runbook.

Docs: [`databricks catalogs`](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/cli/reference/catalogs-commands),
[`external-locations`](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/cli/reference/external-locations-commands),
[`storage-credentials`](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/cli/reference/storage-credentials-commands).
