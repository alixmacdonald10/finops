# In-guest setup via VM Run Command: installs the VC++ x64 runtime (Microsoft-signature checked)
# and Neovim (signature/digest checked), sets Windows Update
# to Sunday 01:00 with 08-17 active hours, and registers a logon task that generates SSH keys
# for GitHub / Azure DevOps. Script source: scripts/setup.ps1.

resource "azurerm_virtual_machine_run_command" "setup" {
  name               = "setup"
  location           = local.location
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  tags               = local.tags

  source {
    script = templatefile("${path.module}/scripts/setup.ps1", {
      neovim_version = var.neovim_version
    })
  }
}
