#!/usr/bin/env bash
# The workspace's managed RG has a fixed name (rg-dbxlab-eus2-managed). Right
# after a destroy, Azure can still be deleting it asynchronously, and creating
# a new workspace then fails with a name conflict. Wait (up to WAIT_MINUTES)
# until the RG is absent or in any state other than "Deleting".
# Needs only Microsoft.Resources/subscriptions/resourceGroups/read (custom
# role from bootstrap).
set -euo pipefail

rg="${MANAGED_RG:-rg-dbxlab-eus2-managed}"
deadline=$(( $(date +%s) + ${WAIT_MINUTES:-30} * 60 ))
err="${RUNNER_TEMP:-/tmp}/rg-check.err"

while :; do
  if state=$(az group show --name "$rg" --query properties.provisioningState -o tsv 2> "$err"); then
    if [ "$state" != "Deleting" ]; then
      echo "Managed RG exists (state: ${state}); a workspace already owns it or it's ready."
      exit 0
    fi
    echo "Managed RG is still deleting from the previous destroy; waiting..."
  elif grep -q "ResourceGroupNotFound" "$err"; then
    echo "Managed RG is absent; safe to create the workspace."
    exit 0
  else
    echo "::error::Couldn't read the managed RG state (does the apply identity have the bootstrap 'dbxlab resource group metadata reader' role?)."
    sed -E 's/[0-9a-fA-F-]{36}/<redacted-guid>/g' "$err" >&2
    exit 1
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "::error::Managed RG still deleting after ${WAIT_MINUTES:-30} minutes. Check it in the portal, then re-run."
    exit 1
  fi
  sleep 30
done
