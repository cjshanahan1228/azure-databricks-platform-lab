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
6. **Lakehouse storage firewall:** public network access is `Disabled`, the
   default action is `Deny` with **no** trusted-services bypass, and a
   resource-instance rule allows only the lab's access connector (Microsoft's
   documented pattern for UC with a firewalled account).
7. **Drift workflow and `pip` Dependabot** aren't added: drift is for the
   always-on model (not chosen), and there's no Python until phase 2.
