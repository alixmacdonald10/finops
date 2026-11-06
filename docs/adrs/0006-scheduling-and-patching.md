# 6. Scheduling and patching

- Date: 2026-11-06
- Status: Accepted

## Context

The VM should run during UK working hours (08:00-17:00 Europe/London) and install patches on Sunday at 01:00, while being deallocated the rest of the time to save cost.

The start/stop runbook only needs to read, start and deallocate the VM. The built-in roles that allow this are broader. A custom role with only those actions would need `Microsoft.Authorization/roleDefinitions/write`, which the deploying identity may not have.

## Decision

- **Stop:** DevTest Labs global auto-shutdown deallocates the VM daily at 17:00 (`auto_shutdown_time`, VM timezone).
- **Start:** an Automation account with a managed identity runs a `vm-power` PowerShell runbook on schedules: Mon-Fri 08:00 start, Sunday 00:45 start, Sunday 03:00 deallocate.
- **Runbook runtime:** the runbook runs on a PowerShell 7.4 runtime environment (`azurerm_automation_runtime_environment`) with the Az 12.3.0 default package. Bump the Az version when Azure deprecates it.
- **Automation identity role:** the built-in `Virtual Machine Contributor` role is assigned to the Automation account's managed identity, scoped to this VM only.
- **Patching:** in-guest Windows Update policy (set by `scripts/setup.ps1`): auto download, scheduled install Sunday 01:00 with automatic reboot, active hours 08:00-17:00. Azure Update Manager now supports this image and could replace this later.
- **DST:** schedule start times are computed with the correct UK offset (GMT or BST) at apply time; Azure then keeps wall-clock time across clock changes.
- `enable_auto_start = false` removes the Automation account entirely.

## Consequences

- Without auto start, the VM never starts automatically and Sunday patching does not happen unless it is started by hand.
- Patching depends on the VM being started for the Sunday window; a failed runbook means updates wait until next use.
- `Virtual Machine Contributor` also allows Run Command and extensions, so anyone who can edit or run runbooks in the Automation account can run code as SYSTEM on the VM. Access to the Automation account must stay limited to the VM owner.
- A tighter custom role (read, start, deallocate) can replace it if role-definition rights are available.
