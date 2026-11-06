# 3. Cost optimisation

- Date: 2026-11-06
- Status: Accepted

## Context

The VM must cost as little as possible while still running Windows Server with a desktop, and only needs to be available during UK working hours.

## Decision

- **Size:** `Standard_B2als_v2` (2 vCPU / 4 GiB, burstable). Cheapest size that runs Windows Server with Desktop Experience acceptably.
- **Disk:** `Standard_LRS` HDD OS disk, small-disk image grown to 64 GiB (`os_disk_size_gb`). Switch `os_disk_type` to `StandardSSD_LRS` if too slow.
- **No backups:** the VM is ephemeral; nothing on it is the only copy.
- **Deallocate outside working hours:** daily DevTest auto-shutdown at 17:00 and Automation runbook start at 08:00 Mon-Fri (see [ADR 6](0006-scheduling-and-patching.md)). Deallocated VMs incur no compute charge.
- **Automation:** runbook minutes fit in the free 500 min/month.
- **Boot diagnostics:** managed storage, so no storage account.
- **Spot (optional):** `use_spot = true` gives a large further discount, with eviction policy `Deallocate`.

## Consequences

- Burstable CPU and HDD make the desktop slower, especially at first logon and during updates.
- The Standard static public IP is billed (about £3/month) even while the VM is deallocated.
- The OS disk is billed while deallocated.
- With spot, the VM can be evicted mid-session.
