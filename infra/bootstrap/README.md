# Bootstrap (run once, locally, by Colin)

This stack is the persistent foundation that CI can't create for itself:

| Resource | Why |
|---|---|
| `rg-dbxlab-state` + `stdbxlabtf<4 chars>` / container `tfstate` | Remote state for every stack. Shared keys **disabled**, Entra ID only, blob versioning + 30-day soft delete, `prevent_destroy`. |
| `rg-dbxlab-eus2` (empty) | The lab RG. Persistent so the CI roles and budget survive every nightly destroy; `platform` fills and empties it. |
| `id-gh-dbxlab-plan` | Read-only CI identity. Federated to `pull_request` and `ref:refs/heads/main`. Reader on the lab RG + Storage Blob Data Contributor on the state container (state locking is a blob lease, which is a write). |
| `id-gh-dbxlab-apply` | Deploy/destroy CI identity. Federated to the `lab` and `lab-destroy` GitHub environments only. Contributor on the lab RG, Storage Blob Data Contributor on the state container, and **Role Based Access Control Administrator conditioned to Storage Blob Data Contributor + Cognitive Services OpenAI User only**. |
| `budget-dbxlab-monthly` | $25/month, filtered to the lab RG, the Databricks managed RG and the state RG. Emails at 50 %, 80 %, 100 % actual and 100 % forecast. |
| Resource provider registrations | Microsoft.Databricks and friends, so the CI identities never need subscription-level rights. |

It costs pennies a month (a near-empty storage account). It creates nothing that bills by the hour.

## Your first hands-on step

You need: Terraform ≥ 1.9, Azure CLI, GitHub CLI, and Owner (or Contributor +
User Access Administrator) on the **Shanahan Enterprises Development**
subscription.

1. **Sign in to the right tenant and subscription.**

   ```sh
   az login --tenant <tenant-id>
   az account set --subscription <development-subscription-id>
   az account show --query "{name:name, user:user.name}" -o table   # sanity check
   ```

2. **Fill in your variables** (the file is git-ignored; IDs never get committed):

   ```sh
   cd infra/bootstrap
   cp terraform.tfvars.example terraform.tfvars
   # edit: subscription_id, tenant_id, budget_contact_emails
   ```

3. **Init and plan. Read the plan before you apply.**

   ```sh
   terraform init
   terraform plan -out=bootstrap.tfplan
   ```

   Expect 18 resources to add and nothing to change or destroy. Things
   worth reading closely (each is an interview talking point):
   - the four `azurerm_federated_identity_credential` subjects: which GitHub
     contexts can become which identity;
   - `apply_rbac_admin_conditioned`: the ABAC condition that stops the apply
     identity from granting itself Owner;
   - the budget's `ResourceGroupName` filter, which includes a managed RG that
     doesn't exist yet.

4. **Apply.**

   ```sh
   terraform apply bootstrap.tfplan
   ```

   If it fails with `AuthorizationFailed` on the budget, you need Cost
   Management Contributor (Owner includes it). If a role assignment fails with
   `PrincipalNotFound`, Entra replication lagged: re-run `terraform apply`.

5. **Set the GitHub repo variables.** Review the commands first. They set
   *variables*, not secrets: identifiers only, nothing that grants access by
   itself.

   ```sh
   terraform output -raw github_variables_commands      # read them
   terraform output -raw github_variables_commands | bash
   gh variable set LAB_ADMIN --repo cjshanahan1228/azure-databricks-platform-lab --body '<your Entra UPN / Databricks login>'
   ```

   Once these exist, the **Plan (platform)** check on this PR starts running
   instead of being skipped. Re-run it from the PR's Checks tab.

6. **Move bootstrap's own state into the state account** (so it isn't only on
   your laptop):

   ```sh
   cat > backend.tf <<EOT
   terraform {
     backend "azurerm" {
       resource_group_name  = "rg-dbxlab-state"
       storage_account_name = "$(terraform output -raw state_storage_account_name)"
       container_name       = "tfstate"
       key                  = "bootstrap.tfstate"
       use_azuread_auth     = true
     }
   }
   EOT
   terraform init -migrate-state      # answer "yes"
   rm terraform.tfstate terraform.tfstate.backup   # after confirming the migration worked
   ```

   `backend.tf` is git-ignored because it names your state account. Keep it
   locally for future bootstrap runs.

7. **Note two values for the next step** (the Databricks account console):

   ```sh
   terraform output apply_client_id        # application ID of id-gh-dbxlab-apply
   terraform output apply_principal_name
   ```

Then continue with **Step 2** in [docs/learning/phase-1.md](../../docs/learning/phase-1.md#your-hands-on-steps-in-order).

## If the first deploy can't create the workspace

Design §7 flagged an open question: can a **resource-group-scoped**
Contributor create a VNet-injected workspace, given that Databricks creates the
managed RG `rg-dbxlab-eus2-managed`? If the first apply fails with an
authorization error on that managed RG, set
`apply_identity_subscription_contributor = true` in `terraform.tfvars`,
re-apply bootstrap, re-run the deploy, and record the outcome in the README.
It's a broader grant, so only use it if it's actually needed.
