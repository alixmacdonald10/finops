# 7. In-guest setup via Run Command

- Date: 2026-11-09
- Status: Accepted

## Context

The VM should come up with Neovim installed, the Sunday patch policy applied and SSH keys ready for GitHub and Azure DevOps, without a custom image.

The Windows Server 2025 image does not include the Visual C++ 2015-2022 x64 runtime. Neovim's Windows build links against it, so without it `nvim.exe` fails to start with `vcruntime140.dll` not found.

## Decision

- Run `infra/scripts/setup.ps1` once as SYSTEM via VM Run Command, rendered with `templatefile()`.
- **VC++ runtime:** install the latest VC++ x64 redistributable before Neovim, unless `vcruntime140.dll` already exists in `System32`. Download from Microsoft's permalink `https://aka.ms/vs/17/release/vc_redist.x64.exe` over HTTPS. Microsoft publishes no digest for this link, so require a valid Authenticode signature whose signer is `O=Microsoft Corporation`, otherwise fail. Install with `/install /quiet /norestart`; treat exit codes 0, 1638 (newer version present) and 3010 (reboot required) as success.
- **Neovim:** download the `neovim_version` MSI from GitHub releases. Before installing, require a valid Authenticode signature, or if unsigned, a SHA-256 match against the digest GitHub publishes for the release asset. Otherwise fail.
- **Windows Update:** set the policy described in [ADR 6](0006-scheduling-and-patching.md).
- **SSH keys:** a logon scheduled task generates, per user, `id_ed25519` (GitHub) and `id_rsa` 4096 (Azure DevOps, where RSA is the reliably supported type) with no passphrase, plus `~/.ssh/config`.
- **SSH transport:** GitHub and Azure DevOps both use port 22 directly, as outbound 22 is allowed (see [ADR 4](0004-network-security.md)).

## Consequences

- Keys have no passphrase because the VM is ephemeral; they must be revoked in GitHub / Azure DevOps when the VM is destroyed.
- If `allow_ssh_outbound = false`, git over SSH stops working; use HTTPS with Git Credential Manager instead.
- `~/.ssh/config` is only written if missing, so users on an existing VM keep any earlier config.
- The VC++ runtime version is not pinned. Each build gets the latest Microsoft-supported release, and Windows Update services it after that. The download adds about 25 MB to first setup.
- Changing the script re-runs Run Command on the next apply. Steps whose result is already present (VC++ runtime, Neovim) are skipped.
