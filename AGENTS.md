# Overview

This repo contains the IaC code to spin up a virtual machine in Azure.

It is designed to be spun up and down repeatedly.

It is always deployed into a pre-existing resource group (`resource_group_name`); OpenTofu must never create or delete the resource group.

A dedicated VNet is created by default; `create_vnet = false` uses an existing VNet (`vnet_name`). The VM always gets its own subnet, which OpenTofu creates.

## Specification

- must run Windows Server 2025 (pay-as-you-go licence; Windows 11 is not used because it needs Windows E3/E5/VDA or Visual Studio subscription rights)
- should be configured for UK working hours 8am to 5pm (Europe/London)
- should be configured to apply patches on Sunday at 1am
- requires only a small disk (small-disk image, 64 GiB); it does not need backups as it is designed to be ephemeral

### Usability
The following requirements are nice to have:
- should be configured to load up with Neovim installed
- should be configured to generate SSH keys suitable for GitHub and Azure DevOps

### Cost
- must be as low cost as possible whilst still allowing the OS to function
- must be configured to auto shut down outside of working hours

### Security

- VM must only be accessible from my IP via RDP
- must use a secure generated local admin password (Entra ID login is not used)
- must allow all outbound traffic on port 443 (HTTPS), 53 (DNS) and 80 (HTTP, for Windows Update and CRL/OCSP checks)
- should allow outbound traffic on port 22 (SSH, for git repo work); can be disabled via `allow_ssh_outbound`
- must allow outbound TCP 1688 to Azure KMS IPs only (Windows Server licence activation)
- all other outbound Internet traffic must be denied

### Code Standards
- all IaC (.tf files, `terraform.tfvars.example`, `.terraform.lock.hcl`, `scripts/`) lives in `infra/`; run `tofu` and `trivy` commands from `infra/`
- must use OpenTofu, not Terraform (`tofu` CLI; providers from registry.opentofu.org)
- must run `tofu fmt -recursive` after each batch of changes
- must run `tofu validate` after each batch of changes
- must run `trivy config .` IaC scanning after each batch of changes to prevent security issues
- any trivy ignore (`#trivy:ignore:<ID>`) must have a comment explaining why
- the IAC must be split into discrete .tf files handling individual components (networking, storage, iam, etc)
- each .tf file should have a brief explanation in comments at the top of the file

### Architecture Decision Records
- significant decisions (architecture, cost, security, networking, auth, scheduling, tooling) must be recorded as an ADR in `docs/adrs/`
- ADRs use the Nygard format: title, date, status, Context, Decision, Consequences
- files are numbered sequentially `NNNN-short-title.md` and listed in the `docs/adrs/README.md` index
- do not rewrite an accepted decision; write a new ADR and mark the old one `Superseded by NNNN`
- `README.md` stays brief (diagram, schedule, cost and network summaries, usage) and links to ADRs for the reasoning
- when code changes alter a recorded decision, update or supersede the relevant ADR in the same batch

## Agent rules

- never read, print or copy `*.tfvars` (except `*.tfvars.example`), `*.tfstate*` or `.terraform/` contents; state contains the admin password
- do not run `tofu apply` / `tofu destroy` without explicit user confirmation (costs money, changes real infra)
- `infra/scripts/setup.ps1` is rendered with `templatefile()`: escape literal `${` as `$${` and avoid `%{`
