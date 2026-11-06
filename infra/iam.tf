# Identity and access: the Automation account's role on the VM, used by the start/stop runbook.
# VM sign-in is local admin password only (see docs/adrs/0005-local-admin-password-auth.md).

# Scoped to this VM only, but "Virtual Machine Contributor" is broader than start/deallocate:
# it includes Run Command and extensions (code execution as SYSTEM).
# See docs/adrs/0006-scheduling-and-patching.md.
resource "azurerm_role_assignment" "automation_vm" {
  count = var.enable_auto_start ? 1 : 0

  scope                = azurerm_windows_virtual_machine.this.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_automation_account.this[0].identity[0].principal_id
}
