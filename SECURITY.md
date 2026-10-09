# Security policy

This repository is a **personal lab**: an Azure Databricks platform built
entirely from Terraform and GitHub Actions to learn and demonstrate the
platform. It only ever processes public datasets. Security reports are still
welcome.

## Reporting

- Preferred: [open a private security advisory](https://github.com/cjshanahan1228/azure-databricks-platform-lab/security/advisories/new)
  (GitHub private vulnerability reporting).
- Otherwise email the address on <https://www.colinshanahan.dev/#contact> with
  "security" in the subject.

Please don't open a public issue for anything exploitable. I aim to
acknowledge within a few days.

## Scope

In scope: the Terraform and GitHub Actions workflows in this repo, in
particular anything that would let someone outside the repo obtain Azure
access through the OIDC federation, start or keep lab resources running, or
read data in the lab's storage. Out of scope: Azure, Databricks and GitHub
platform issues (report those to the vendor), social engineering, denial of
service.

## Design notes

- **No stored secrets.** CI authenticates to Azure with GitHub OIDC tokens
  exchanged for user-assigned managed identities. The repo holds only
  *variables* (client, tenant and subscription IDs, the state account name),
  which are identifiers, not credentials.
- **Two identities.** A read-only *plan* identity (pull requests and `main`)
  and an *apply* identity that only the `lab` (required reviewer) and
  `lab-destroy` environments can use, both restricted to `main`.
- **Least privilege.** The apply identity is Contributor on the lab resource
  group only, and can only create role assignments for Storage Blob Data
  Contributor and Cognitive Services OpenAI User (an ABAC-conditioned Role
  Based Access Control Administrator assignment).
- **Shared keys are disabled** on both storage accounts (Terraform state and
  the lakehouse). Access is Entra ID only. The lakehouse account has public
  network access disabled and is reached through private endpoints.
- Actions are pinned to full commit SHAs and the repository enforces it.
  Workflow logs are public, so subscription and tenant IDs are masked.
