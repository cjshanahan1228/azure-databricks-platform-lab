# Architecture decisions

| ADR | Title | Status |
|---|---|---|
| [0001](0001-databricks-platform-lab-design.md) | Azure Databricks platform lab design | Accepted 2026-10-09 |

## Phase 1 implementation notes (where the build differs from ADR-0001)

1. **Workspace stack isn't planned on PRs.** ADR-0001 §7 has `ci.yml` plan
   `workspace` "only if a workspace exists". The plan identity is only an Azure
   *Reader*, which doesn't make it a Databricks workspace user, so it can't
   refresh UC objects or the cluster policy. Instead, `deploy.yml` plans and
   applies `workspace` in the approved `apply` job, right after `platform`, and
   puts that plan in the job summary. On a first deploy it couldn't be planned
   earlier anyway: the workspace doesn't exist yet.
2. **The approved plan is re-created, not uploaded.** ADR-0001 says `deploy.yml`
   "uploads the plan as an artifact" and applies "that exact plan". Artifacts on
   a public repo are downloadable and the plan contains subscription-scoped
   resource IDs. So the plan job publishes a redacted summary plus a digest of
   the change set, and the apply job re-plans and **refuses to apply** unless
   the digest matches what was approved.
3. **Workspace stack is gated by `DEPLOY_WORKSPACE_STACK`.** The UC objects
   need metastore grants that Colin makes by hand (ADR-0001 §5), and the
   learning track has him build the UC chain by hand first. Until the variable
   is `"true"`, deploys create the platform only.
4. **The budget filter also includes `rg-dbxlab-state`**, so the whole lab
   (including the persistent bit) counts against the $25.
5. **The keep-alive is a date variable with a 7-day ceiling**
   (`LAB_KEEP_ALIVE_UNTIL`), so a forgotten or mistyped value can't keep the lab
   up indefinitely.
6. **Lakehouse storage firewall (amended 2026-10-10 after review):** the
   account is *firewalled to the access connector*: public network access
   "Enabled from selected networks", default action `Deny`, **no**
   trusted-services bypass, no IP/VNet rules, one resource-instance rule for
   the lab's access connector, and private endpoints for the compute plane.
   The first version set public network access to `Disabled`. Microsoft's
   docs disagree on whether resource-instance rules still apply then: the
   Databricks page says it's optional and the managed identity can bypass it,
   but the Storage "set default access" page says `Disabled` allows traffic
   "only through a private endpoint". The Databricks page also calls
   "Enabled from selected virtual networks and IP addresses" the standard
   approach, so the lab uses that. The UC control plane isn't in the VNet, and
   it needs the public endpoint (behind the resource-instance rule) for
   validation and credential vending.
7. **Drift workflow and `pip` Dependabot** aren't added: drift is for the
   always-on model (not chosen), and there's no Python until phase 2.
8. **Metastore auto-assignment is a hard prerequisite** (amended §5). The
   workspace is new on every deploy and the apply identity isn't an account
   admin, so auto-assignment of new eastus2 workspaces is the only unattended
   path. `deploy.yml` checks the assignment right after the platform apply.
9. **UC names:** storage credential and external location names carry a
   per-deploy suffix. The catalog stays `dbxlab` for phase 2, so an orphaned
   catalog blocks the next deploy; `deploy.yml` checks for that and points to
   [the runbook](../runbooks/orphaned-unity-catalog-objects.md).
10. **Deploy/destroy concurrency** is job-level with `queue: max`, and destroy
    cancels unapproved deploys first. See
    [the runbook](../runbooks/deploy-destroy-concurrency.md).
11. **Managed RG wait:** the managed RG name is fixed, so deploy waits (up to
    30 minutes) while a previous `rg-dbxlab-eus2-managed` is still `Deleting`.
    For that, bootstrap gives the apply identity a custom role with only
    `Microsoft.Resources/subscriptions/resourceGroups/read` at subscription
    scope.
12. **Phase 3 Azure OpenAI goes in `bootstrap`** (persistent), because of the
    48-hour soft-delete name lock. Recorded in ADR-0001 §8 and §14.
13. **Watch item for the first plan:** azurerm 5.9.0 calls `listKeys` when it
    refreshes a storage account. The read-only plan identity gets 403, and the
    provider tolerates that (it treats 401/403 as "no keys" and carries on).
    Shared keys are disabled anyway, and `storage_use_azuread = true` plus
    `data_plane_available = false` keep every other storage call on ARM/Entra.
    If the first PR plan fails on storage, this is the first place to look.
