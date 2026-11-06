# 5. Local admin password authentication only

- Date: 2026-11-06
- Status: Accepted

## Context

RDP sign-in needs to be secure. Microsoft Entra ID login was previously optional (`enable_entra_login`). It required the `AADLoginForWindows` extension, a system-assigned identity on the VM and a `Virtual Machine Administrator Login` role assignment. It also only works from Windows `mstsc` with web account sign-in; Linux RDP clients (e.g. `xfreerdp`) generally cannot use it. In practice the local password was always needed.

## Decision

- Use only the local admin account with a generated password: 24 characters, at least 2 each of lower, upper, numeric and special (`random_password` in `infra/compute.tf`).
- Remove the Entra login extension, VM identity, role assignment and `enable_entra_login` variable.

## Consequences

- Fewer resources and role assignments; the deploying identity only needs to create the Automation role assignment.
- The password is stored in local state (see [ADR 1](0001-opentofu-with-local-state.md)) and read with `tofu output -raw admin_password`.
- RDP is limited to the user's IP (see [ADR 4](0004-network-security.md)), which reduces the risk of password-only sign-in.
- No MFA on sign-in. Entra login could be reintroduced in a new ADR if this changes.
