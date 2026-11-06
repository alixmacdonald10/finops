# 4. Network security

- Date: 2026-11-06
- Status: Accepted

## Context

The VM has a public IP for RDP. Inbound access must be limited to the user's IP, and outbound Internet access limited to what the OS and git workflows need.

## Decision

One NSG, attached to both the subnet and the NIC.

**Inbound**

- RDP 3389 (TCP and UDP) from `allowed_ip/32` only. `allowed_ip` is auto-detected via `api.ipify.org` when not set.
- Everything else denied.

**Outbound to Internet**

| Port | Protocol | Why |
|---|---|---|
| 443 | TCP + UDP | HTTPS; UDP so QUIC / HTTP3 works |
| 53 | TCP + UDP | DNS |
| 80 | TCP | Windows Update, CRL and OCSP checks |
| 22 | TCP | git over SSH (GitHub, Azure DevOps); `allow_ssh_outbound = false` disables it |
| 1688 | TCP | Windows activation, to Azure KMS IPs only (`azure_kms_ips` in `infra/network.tf`) |

All other outbound Internet traffic is denied.

## Consequences

- If the user's IP changes, `tofu apply` must be re-run (or `allowed_ip` set) before RDP works again.
- Azure platform traffic to 168.63.129.16 (DNS, VM agent) is not affected by NSG rules.
- If Microsoft changes the KMS IPs, activation fails until `azure_kms_ips` is updated.
- Tools using other ports (e.g. 3306, 5432, custom SSH ports) are blocked unless a rule is added.
- With port 22 open, GitHub SSH no longer needs routing via `ssh.github.com:443` (see [ADR 7](0007-in-guest-setup-run-command.md)).
