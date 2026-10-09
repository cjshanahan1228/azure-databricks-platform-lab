#!/usr/bin/env bash
# Usage: plan-summary.sh <terraform dir> <plan file> <title>
# Writes a REDACTED plan summary to plan-summary.md (and the job summary) and
# prints the change digest (sha256 of the sorted address+actions list) on
# stdout. The repo is public, so every GUID (subscription, tenant, principal
# IDs) is replaced before anything leaves the runner.
set -euo pipefail

dir="$1"; plan="$2"; title="$3"
redact() {
  sed -E -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<redacted-guid>/g' \
         -e 's/adb-[0-9]+\.[0-9]+\.azuredatabricks\.net/<workspace-host>/g'
}

terraform -chdir="$dir" show -json "$plan" > plan.json
changes=$(jq -c '[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])
                  | {address, actions: .change.actions}] | sort_by(.address)' plan.json)
digest=$(printf '%s' "$changes" | sha256sum | cut -d' ' -f1)
add=$(jq '[.[] | select(.actions | index("create"))] | length' <<<"$changes")
chg=$(jq '[.[] | select(.actions == ["update"])] | length' <<<"$changes")
del=$(jq '[.[] | select(.actions | index("delete"))] | length' <<<"$changes")

terraform -chdir="$dir" show -no-color "$plan" | redact > plan.txt
# Keep the comment under GitHub's 65,536-char limit.
if [ "$(wc -c < plan.txt)" -gt 55000 ]; then
  head -c 55000 plan.txt > plan.trunc && mv plan.trunc plan.txt
  printf '\n... (truncated; see the job log for the full plan)\n' >> plan.txt
fi

{
  echo "### ${title}"
  echo
  echo "**${add} to add, ${chg} to change, ${del} to destroy** (replacements count as add + destroy)."
  echo
  echo "Change digest: \`${digest:0:16}\`"
  echo
  jq -r '.[] | "- `\(.actions | join("/"))` \(.address)"' <<<"$changes" | head -200
  echo
  echo "<details><summary>Full plan (GUIDs redacted)</summary>"
  echo
  echo '```'
  cat plan.txt
  echo '```'
  echo
  echo "</details>"
} > plan-summary.md

cat plan-summary.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "$digest"
