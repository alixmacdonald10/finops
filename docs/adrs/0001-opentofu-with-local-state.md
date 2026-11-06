# 1. OpenTofu with local state

- Date: 2026-11-06
- Status: Accepted

## Context

The VM is a single-user, ephemeral dev box that is created and destroyed often. It needs IaC that is open source and does not depend on a paid backend.

## Decision

- Use OpenTofu (`tofu` CLI) with providers from `registry.opentofu.org`, not Terraform.
- Keep all IaC in `infra/`, split into one `.tf` file per component.
- Use local state. No remote backend.
- Run `tofu fmt -recursive`, `tofu validate` and `trivy config .` after each batch of changes.

## Consequences

- `terraform.tfstate` contains the generated admin password in plain text. It must stay on the deploying machine and is gitignored, along with `*.tfvars` and saved plans.
- Losing local state means the resources it created must be removed by hand.
- Only one person can safely manage a given deployment.
