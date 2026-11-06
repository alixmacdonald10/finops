# 2. Windows Server 2025 with pay-as-you-go licence

- Date: 2026-11-06
- Status: Accepted

## Context

A Windows desktop is needed. Running Windows 11 in Azure requires Windows E3/E5/VDA or Visual Studio subscription licence rights, which cannot be assumed.

## Decision

- Use Windows Server 2025 Datacenter (Desktop Experience, small-disk Gen2 image) with the pay-as-you-go licence included in the hourly VM price. No Azure Hybrid Benefit.
- Enable Trusted Launch (Secure Boot + vTPM).
- Set the VM timezone to `GMT Standard Time` (UK, with DST).

## Consequences

- No separate Windows licence is needed; the licence is only billed while the VM runs.
- Windows Server activates against Azure KMS on TCP 1688, so that egress must be allowed (see [ADR 4](0004-network-security.md)).
- Some desktop apps assume a client OS and may need extra Windows features installed.
