#!/usr/bin/env bash
# Pre/post-deploy checks against the lab workspace, using the Azure CLI
# session from azure/login (the apply identity). Nothing identifying is
# printed: the workspace URL, resource ID and token are masked, and API
# responses are written to a temp file, never echoed.
#
#   databricks-checks.sh metastore        fail unless a UC metastore is assigned
#   databricks-checks.sh orphan-catalog   fail if catalog "dbxlab" exists in the
#                                         metastore but not in workspace state
set -euo pipefail

mode="${1:?usage: databricks-checks.sh metastore|orphan-catalog}"
catalog="${CATALOG_NAME:-dbxlab}"
repo_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-cjshanahan1228/azure-databricks-platform-lab}/blob/main"

out=$(terraform -chdir=infra/platform output -json)
host=$(jq -r '.workspace_url.value // empty' <<<"$out")
rid=$(jq -r '.workspace_resource_id.value // empty' <<<"$out")
if [ -z "$host" ] || [ -z "$rid" ]; then
  echo "::error::No workspace in the platform state."
  exit 1
fi
echo "::add-mask::$host"
echo "::add-mask::$rid"

# 2ff814a6-... is the well-known Azure Databricks resource (application) ID.
token=$(az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken -o tsv)
echo "::add-mask::$token"
resp="${RUNNER_TEMP:-/tmp}/dbx-check.json"

api() { # api <path> -> prints HTTP status, body in $resp
  curl -sS -o "$resp" -w '%{http_code}' \
    -H "Authorization: Bearer ${token}" \
    -H "X-Databricks-Azure-Workspace-Resource-Id: ${rid}" \
    "${host}$1"
}

case "$mode" in
  metastore)
    # A brand-new workspace can take a minute or two to be auto-assigned.
    attempts="${ATTEMPTS:-10}"
    for i in $(seq 1 "$attempts"); do
      code=$(api /api/2.1/unity-catalog/current-metastore-assignment || true)
      if [ "$code" = "200" ] && jq -e '.metastore_id // empty' "$resp" > /dev/null; then
        echo "Unity Catalog metastore is assigned to the new workspace."
        exit 0
      fi
      echo "Attempt ${i}/${attempts}: no metastore assignment yet (HTTP ${code})."
      [ "$i" -lt "$attempts" ] && sleep 30
    done
    echo "::error title=No Unity Catalog metastore assigned::The new workspace isn't attached to a metastore. Enable auto-assignment of new eastus2 workspaces on the East US 2 metastore (account console > Catalog > metastore > Configuration > Workspace assignment), then re-run. Runbook: ${repo_url}/docs/learning/phase-1.md#step-2-colin-become-account-admin-and-check-for-a-metastore--20-min-0"
    exit 1
    ;;
  orphan-catalog)
    if terraform -chdir=infra/workspace state list 2>/dev/null | grep -q '^module.unity_catalog.databricks_catalog.this$'; then
      echo "Catalog ${catalog} is managed by this state."
      exit 0
    fi
    code=$(api "/api/2.1/unity-catalog/catalogs/${catalog}" || true)
    if [ "$code" = "200" ]; then
      echo "::error title=Orphaned Unity Catalog objects::Catalog '${catalog}' already exists in the metastore but isn't in Terraform state (a previous destroy didn't remove it). Follow ${repo_url}/docs/runbooks/orphaned-unity-catalog-objects.md, then re-run."
      exit 1
    fi
    echo "No orphaned '${catalog}' catalog (HTTP ${code})."
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
