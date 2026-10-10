#!/usr/bin/env bash
# Copies the platform stack outputs the workspace stack needs into
# infra/workspace/platform.auto.tfvars.json (git-ignored) and masks the
# identifying ones in the public log. Exits 3 if there is no workspace.
set -euo pipefail

out=$(terraform -chdir=infra/platform output -json)
if [ "$(jq -r '.workspace_url.value // empty' <<<"$out")" = "" ]; then
  echo "No workspace in the platform state."
  exit 3
fi

for k in workspace_url workspace_resource_id access_connector_id lakehouse_url; do
  echo "::add-mask::$(jq -r ".${k}.value" <<<"$out")"
done

jq '{workspace_url: .workspace_url.value,
     workspace_resource_id: .workspace_resource_id.value,
     access_connector_id: .access_connector_id.value,
     lakehouse_url: .lakehouse_url.value}' <<<"$out" > infra/workspace/platform.auto.tfvars.json
echo "Wrote infra/workspace/platform.auto.tfvars.json"
