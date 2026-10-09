# Phase 1 learning track: workspace, networking, identity, CI/CD

This is my guide for phase 1. The automation in this repo builds the platform;
these notes are for **understanding** it well enough to explain every box in
the diagram in an interview. Steps marked **[Colin]** are deliberately manual.

How to use it: read the concepts first (about an hour), skim the linked docs
for anything that doesn't click, then do the hands-on steps in order. Each
hands-on step says what it costs.

---

## Concepts first

Each concept: what it is, how it maps to something I already know, and where
it lives in this repo.

### 1. Account vs workspace (and the three kinds of admin)

- **Account**: the top-level Databricks tenant-wide object, managed at
  <https://accounts.azuredatabricks.net>. Holds users/groups/service
  principals (synced from Entra ID), **Unity Catalog metastores**, and the list
  of workspaces. One per Entra tenant.
- **Workspace**: one Azure resource (`dbw-dbxlab-eus2`) = one URL with
  notebooks, clusters, jobs and SQL. Many workspaces can share one metastore.
- **Account admin** manages the account (metastores, identities). The first one
  must be an Entra Global Administrator signing in for the first time, which is
  me. **Workspace admin** manages one workspace; anyone with Contributor/Owner
  on the Azure resource becomes one automatically, which is how the CI apply
  identity becomes an admin with no extra setup. **Metastore admin** owns the
  Unity Catalog metastore and can grant privileges on it.
- *Maps to:* the Azure split between a tenant (Entra) and a subscription
  resource, or an AKS cluster (resource) vs Kubernetes RBAC inside it.

### 2. Control plane vs compute plane

- The **control plane** (web app, REST API, job scheduler, Unity Catalog) runs
  in Databricks' own Azure subscription.
- The **classic compute plane** (cluster VMs) runs in *my* subscription, in the
  Databricks-managed RG `rg-dbxlab-eus2-managed`, attached to *my* VNet. I can
  see the VMs but can't change them (a deny assignment protects the RG).
- Serverless compute is a third option: compute in Databricks' subscription.
  Not used in phase 1.
- *Maps to:* AKS (Microsoft runs the API server; my node pools run in the
  `MC_` resource group).
- *In this repo:* `infra/modules/databricks-workspace` (`managed_resource_group_name`).

### 3. VNet injection and delegated subnets

- Instead of Databricks creating a VNet for me, the workspace is **injected**
  into my VNet (`vnet-dbxlab-eus2`), so I control the address space, NSGs,
  egress and private endpoints.
- It needs two subnets, **host** ("public" in Databricks' API) and **container**
  ("private"), both **delegated** to `Microsoft.Databricks/workspaces`, each with
  an NSG. Every cluster node gets one IP in each. Databricks adds the NSG rules
  it needs itself (`network_security_group_rules_required = "AllRules"`).
- *Maps to:* subnet delegation for App Service VNet integration or Azure
  Container Instances.
- *In this repo:* `infra/modules/network`.

### 4. Secure cluster connectivity (SCC, "no public IP")

- With `no_public_ip = true`, cluster nodes have **no public IPs** and no open
  inbound ports. Each node opens an **outbound** connection to a relay in the
  control plane, and commands come back over that tunnel. Nothing dials in.
- *Maps to:* the Azure Arc / self-hosted agent pattern: an agent dials out to a
  service, so the firewall needs no inbound rule.

### 5. NAT gateway egress, and why it's required

- With no public IPs, nodes still need to reach the control plane relay, Maven
  and PyPI, and the public dataset. New subnets no longer get Azure's implicit
  "default outbound access" (retired for new VNets), and these subnets set
  `default_outbound_access_enabled = false`, so **without NAT, clusters fail
  to start**.
- The NAT gateway gives all egress **one static public IP** (`pip-ng-dbxlab-eus2`),
  which is also handy for allowlisting.
- It's the biggest standing cost (~$0.045/h + data), which is why the lab is
  ephemeral.

### 6. Private endpoints and private DNS (and the Private Link options)

- The lakehouse account has **public network access disabled**. Clusters reach
  it through **private endpoints** in `snet-pep`: NICs with private IPs for the
  `dfs` (ADLS / ABFS) and `blob` sub-resources.
- **Private DNS zones** (`privatelink.dfs.core.windows.net`,
  `privatelink.blob.core.windows.net`) linked to the VNet make the *normal*
  storage hostname resolve to the private IP inside the VNet. Without the zone
  link, the hostname resolves publicly and the connection is refused.
- Databricks itself has two more Private Link options I did **not** build:
  **back-end** (cluster → control plane over a private endpoint; a cheap
  optional toggle later) and **front-end** (the UI/API only reachable from a
  VNet, plus a `browser_authentication` endpoint for SSO). Front-end would mean
  a VPN or jump host for every demo and self-hosted CI runners. Design §4
  explains why it's written up but not built.
- *Maps to:* exactly the private endpoint + private DNS pattern for any PaaS.

### 7. Unity Catalog basics

- **Hierarchy:** metastore → catalog → schema → table / view / volume /
  function. Names are three-level: `dbxlab.silver.storm_events`.
- **Metastore:** account-level, **one per region**, long-lived, shared by all
  workspaces in that region. This repo never creates or destroys it. Workspaces
  are *assigned* to it.
- **Storage credential:** "how to authenticate to storage" (here, the access
  connector's managed identity).
- **External location:** "this storage path may be accessed with that
  credential" (`abfss://lakehouse@<account>.dfs.core.windows.net/`). External
  locations can't overlap, and their names are unique per metastore.
- **Managed location / storage root:** where UC puts the files of *managed*
  tables. The `dbxlab` catalog's `storage_root` sits under the external
  location.
- **Grants:** SQL `GRANT ... ON <securable> TO <principal>`, inherited
  downward (catalog → schema → table). `databricks_grants` in Terraform is
  *authoritative*: it removes grants it doesn't know about.
- *Maps to:* Azure RBAC scopes (management group → subscription → RG →
  resource), with SQL as the role-assignment syntax.

### 8. Access connector

- `dbac-dbxlab-eus2` is an Azure resource whose only job is to hold a **managed
  identity** that Unity Catalog uses to reach storage. It gets **Storage Blob
  Data Contributor** on the lakehouse account. Users never see storage keys;
  UC hands clusters short-lived, path-scoped credentials.
- It's also what lets UC (the control plane) reach a storage account with
  public access disabled: the account has a **resource-instance rule** for this
  connector.
- *Maps to:* a managed identity on a Function App plus a role assignment, as in
  the portfolio's status function.

### 9. Terraform provider auth, end to end

- GitHub Actions → Azure: OIDC token with subject `repo:…:pull_request`,
  `…:ref:refs/heads/main`, `…:environment:lab` or `…:environment:lab-destroy`,
  exchanged for an Entra token on a user-assigned managed identity. Same
  pattern as the portfolio's `github_main` credential and `id-portfolio-stats`.
- azurerm provider and the state backend: `ARM_USE_OIDC=true`,
  `use_azuread_auth = true` (the state account has shared keys disabled).
- databricks provider: `DATABRICKS_AUTH_TYPE=github-oidc-azure` plus
  `azure_workspace_resource_id`. The same Azure token works against the
  workspace because Contributor on the workspace resource = workspace admin.
- *Maps to:* Azure DevOps workload-identity service connections.

### 10. Cluster policies

- A JSON document that fixes, limits or hides cluster settings. Mine
  (`infra/workspace/policies/single-node-lab.json.tftpl`) forces single-node,
  two VM sizes, 15-minute auto-termination, ≤ 1 DBU/h, single-user (UC) access
  mode, and cost tags that flow onto the VMs.
- Workspace admins can still create clusters without a policy. In a real
  platform, non-admins would get only the policy.
- *Maps to:* Azure Policy, but for one kind of resource inside one workspace.

---

## Free, official resources

Read the first three before deploying; the rest as you hit each topic.

| Topic | Link |
|---|---|
| Architecture (control/compute plane) | [Azure Databricks architecture](https://learn.microsoft.com/en-us/azure/databricks/getting-started/architecture) |
| Core concepts | [Concepts](https://learn.microsoft.com/en-us/azure/databricks/getting-started/concepts) |
| VNet injection | [Deploy Azure Databricks in your VNet](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/vnet-inject) |
| SCC | [Secure cluster connectivity](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/secure-cluster-connectivity) |
| Private Link options | [Private Link concepts](https://learn.microsoft.com/en-us/azure/databricks/security/network/concepts/privatelink-concepts) |
| Default outbound retirement (why NAT) | [Default outbound access](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access) |
| Unity Catalog setup | [Get started with Unity Catalog](https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/get-started) and [Set up Unity Catalog](https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/setup-uc) |
| Access connector | [Managed identities for UC storage](https://learn.microsoft.com/en-us/azure/databricks/connect/unity-catalog/cloud-storage/azure-managed-identities) |
| Grants | [Manage privileges in Unity Catalog](https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/manage-privileges/) |
| Identities and admins | [Manage users, service principals, and groups](https://learn.microsoft.com/en-us/azure/databricks/admin/users-groups/) |
| Cluster policies | [Create and manage compute policies](https://learn.microsoft.com/en-us/azure/databricks/admin/clusters/policies) |
| Terraform | [Databricks Terraform provider](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/terraform/) and the [registry docs](https://registry.terraform.io/providers/databricks/databricks/latest/docs) |
| Budgets | [Create and manage budgets](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets) |
| Course (MS Learn) | [Set up and configure an Azure Databricks environment](https://learn.microsoft.com/en-us/training/paths/azure-databricks-data-engineer-set-up-configure-environment/) |
| Course (MS Learn) | [Secure and govern Unity Catalog objects](https://learn.microsoft.com/en-us/training/paths/azure-databricks-data-engineer-secure-govern-unity-catalog/) |
| Practice for $0 | [Databricks Free Edition](https://www.databricks.com/learn/free-edition) |

---

## Your hands-on steps, in order

Costs assume East US 2 list prices. The lab bills roughly **$0.07/hour while
deployed** (NAT, IP, private endpoints), plus **$0.64–$0.78/hour per running
cluster**. A 4-hour session is about **$2.75–$4.50**.

### Step 1 [Colin]: bootstrap (≈ 30 min, ≈ $0)

Follow [infra/bootstrap/README.md](../../infra/bootstrap/README.md). At the end
you have the state account, both CI identities, the budget, the repo variables
(including `LAB_ADMIN`), and the apply identity's **application (client) ID**
written down.

### Step 2 [Colin]: become account admin and check for a metastore (≈ 20 min, $0)

1. Open <https://accounts.azuredatabricks.net> and sign in with your Entra
   account. As a Global Administrator signing in to an account with no admin
   yet, you become the **account admin**. (If someone is already an admin,
   they need to add you.)
2. **Catalog** (left nav): is there a metastore in **eastus2**?
   - **Yes:** open it. Note its name and owner, and agree on naming if anyone
     else uses it (the lab only adds a `dbxlab` catalog, `dbxlab-*` credential
     and location). If there's an option to **automatically assign new
     workspaces** to it, turn it on. Otherwise you'll assign the lab workspace
     by hand after each deploy (Step 4).
   - **No:** **Create metastore**, region `eastus2`, and leave the ADLS path
     empty (catalogs bring their own storage, as `dbxlab` does). Make yourself
     (or a group you're in) the **metastore admin**.
3. **User management → Service principals → Add service principal →
   Microsoft Entra ID managed**: paste the apply identity's application ID and
   name it `id-gh-dbxlab-apply`. This puts the CI identity in the account so it
   can receive metastore grants (Step 6).

Write down what you found (metastore existed or not, auto-assign on or off).
It goes in the PR and the README.

### Step 3 [Colin]: review and merge the phase 1 PR

Read the plan comment on the PR (it appears once Step 1's variables exist and
the check is re-run), then merge when you're happy. Merging triggers
**Deploy**, which waits for your approval: it's safe to merge now and approve
later, or reject.

### Step 4 [Colin]: first deploy, platform only (≈ 15–25 min, starts billing)

1. **Actions → Deploy → Run workflow** (or use the run started by the merge).
2. Open the **Plan (platform)** job summary and read it. This is the exact
   change set you're approving; the apply job refuses to run if it changes.
3. **Review deployments → lab → Approve.**
4. When it finishes, note the **platform apply** time in the job summary.
5. If the workspace isn't auto-assigned to the metastore: account console →
   Catalog → your metastore → Workspaces → assign `dbw-dbxlab-eus2`.

`DEPLOY_WORKSPACE_STACK` isn't set yet, so Unity Catalog objects aren't
created. That's deliberate: you build them by hand first (Step 6).

### Step 5 [Colin]: explore what was built (≈ 30 min)

In the Azure portal:
- `rg-dbxlab-eus2`: VNet, two NSGs (open one: see the rules Databricks
  added), NAT gateway and its IP, two private endpoints, two private DNS zones
  (look at the A records), the storage account (Networking blade: public
  access disabled; resource instance = the access connector), the access
  connector, Log Analytics, and the workspace.
- `rg-dbxlab-eus2-managed`: empty apart from the workspace's own storage
  account until a cluster starts. Try to delete something: the deny
  assignment stops you.
- **Launch the workspace** from `dbw-dbxlab-eus2`. In **SQL Warehouses**, if a
  starter warehouse was created, check its auto-stop (set it to the minimum)
  or delete it. Serverless SQL bills while running.

### Step 6 [Colin]: hand-build first, then compare (≈ 60–90 min, ≈ $0.64–$0.78/h cluster)

This is design phase 1's "do it by hand before the Terraform".

1. **Create a cluster by hand:** Compute → Create compute → *Single node*,
   `Standard_DS3_v2`, access mode *Dedicated (single user)*, auto-terminate
   after **15** minutes. Start it.
2. Open the cluster's **JSON view** and compare it, line by line, with
   [`infra/workspace/policies/single-node-lab.json.tftpl`](../../infra/workspace/policies/single-node-lab.json.tftpl).
   For every policy line, find the cluster field it controls. Change the
   policy if you'd write a line differently (for example, add a
   `spark_version` allowlist), in a small PR of your own.
3. **Prove the network path** while the cluster runs:
   - In the managed RG, open the cluster VM's NIC: **no public IP**.
   - In a notebook attached to the cluster:
     ```
     %sh
     nslookup <lakehouse-account>.dfs.core.windows.net   # expect 10.60.1.x
     curl -s https://ifconfig.me                          # expect the NAT IP
     ```
   - From your laptop, `nslookup` the same name: a public answer, and any
     request is refused. Screenshot both (redact IDs) for the phase 4 write-up.
4. **Grant the CI identity its metastore privileges** (you must be metastore
   admin). In a notebook or the SQL editor:
   ```sql
   GRANT CREATE CATALOG, CREATE STORAGE CREDENTIAL, CREATE EXTERNAL LOCATION
     ON METASTORE TO `<apply identity application ID>`;
   SHOW GRANTS ON METASTORE;
   ```
5. **Build the UC chain by hand** in Catalog Explorer and SQL, using *scratch*
   names:
   - Catalog → External data → **Credentials** → create `colin-scratch-cred`
     with the access connector's resource ID (portal: access connector →
     Properties).
   - **External locations** → `colin-scratch` at
     `abfss://lakehouse@<lakehouse-account>.dfs.core.windows.net/scratch/`, then
     **Test connection**.
   - Then in SQL:
     ```sql
     CREATE CATALOG colin_scratch
       MANAGED LOCATION 'abfss://lakehouse@<lakehouse-account>.dfs.core.windows.net/scratch/catalog';
     CREATE SCHEMA colin_scratch.demo;
     CREATE TABLE colin_scratch.demo.t (id INT, note STRING);
     INSERT INTO colin_scratch.demo.t VALUES (1, 'hello');
     GRANT SELECT ON TABLE colin_scratch.demo.t TO `account users`;
     SHOW GRANTS ON TABLE colin_scratch.demo.t;
     ```
   - Find the table's files in the storage account's container (you'll be
     refused from the portal, because public access is off). That's the point.
6. **Clean up the scratch objects** (important: external locations can't
   overlap, and the Terraform location covers the whole container):
   ```sql
   DROP CATALOG colin_scratch CASCADE;
   ```
   then delete the `colin-scratch` external location and `colin-scratch-cred`
   in Catalog Explorer. Terminate the cluster.

### Step 7 [Colin]: turn on the workspace stack (≈ 10 min)

```sh
gh variable set DEPLOY_WORKSPACE_STACK --repo cjshanahan1228/azure-databricks-platform-lab --body true
```

Run **Deploy** again and approve. Platform shows no changes; the workspace
stack creates the credential, external location, `dbxlab` catalog with
`bronze` / `silver` / `gold`, grants, and the `lab-single-node` policy.
Compare what Terraform made with what you made by hand in Step 6.

### Step 8 [Colin]: use the policy and watch auto-termination (≈ 20 min, ≈ $0.25)

Create a cluster from **lab-single-node**. Notice which fields you can no
longer change. Leave it idle and check its **Event log** after ~15 minutes
for the auto-termination event. In the managed RG, check that the VM has the
`project` / `owner` / `env` tags from the policy.

### Step 9 [Colin]: destroy and measure (≈ 15–25 min)

**Actions → Destroy → Run workflow → type `destroy`.** Afterwards:
`rg-dbxlab-eus2` is empty, `rg-dbxlab-eus2-managed` is gone, and the job
summary has the destroy times. Add the deploy and destroy times to the README
(phase 1 acceptance criterion).

### Step 10: interview-week keep-alive (when you need it)

```sh
gh variable set LAB_KEEP_ALIVE_UNTIL --repo cjshanahan1228/azure-databricks-platform-lab --body 2026-10-16
gh variable delete LAB_KEEP_ALIVE_UNTIL --repo cjshanahan1228/azure-databricks-platform-lab   # after
```

The nightly destroy skips while today (ET) is on or before that date. A date
more than 7 days ahead is ignored, so a typo can't keep it running for a
month. Standing cost while kept alive is ≈ $1.70/day with no clusters running.

---

## Interview checkpoint

Be able to answer these out loud, without notes, in 1–2 minutes each:

1. "Walk me through the network path from a cluster to the control plane and
   to ADLS. Which hops are private?"
2. "What runs in Databricks' control plane vs in your subscription, and where
   does the data actually live?"
3. "Why didn't you enable front-end Private Link? What would change if this
   held real customer data?"
4. "Why is a NAT gateway required here, and what does it cost you?"
5. "What's the difference between a storage credential, an external location,
   and a managed location?"
6. "How does your CI deploy to Azure and configure Databricks without storing
   a single secret?"
7. "Your apply identity can create role assignments. Why can't it make itself
   Owner?"
8. "How do you stop someone from leaving a big cluster running all weekend?"
   (policy, auto-termination, budget, nightly destroy, and their limits)
9. "Why are `platform` and `workspace` separate Terraform roots?"
10. "What persists between ephemeral deploys, and what breaks if you forget
    that?" (metastore, external location names, workspace URL)

## Notes (fill in as you go)

- Metastore in eastus2 before I started: _yes/no, auto-assign on/off_
- Platform apply time: _
- Workspace apply time: _
- Destroy time: _
- RG-scoped Contributor was enough to create the workspace: _yes/no_
- Surprises:
