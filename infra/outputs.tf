# Outputs: names and addresses needed to connect to and manage the VM. admin_password is sensitive.

output "resource_group" {
  description = "Resource group containing all resources."
  value       = data.azurerm_resource_group.this.name
}

output "vm_name" {
  description = "VM name, for az vm start/deallocate."
  value       = azurerm_windows_virtual_machine.this.name
}

output "public_ip" {
  description = "Public IP to RDP to."
  value       = azurerm_public_ip.this.ip_address
}

output "allowed_ip" {
  description = "Source IP the NSG allows RDP from."
  value       = local.allowed_ip
}

output "admin_username" {
  description = "Local admin username."
  value       = var.admin_username
}

output "admin_password" {
  description = "Local admin password. Read with: tofu output -raw admin_password"
  value       = random_password.admin.result
  sensitive   = true
}

output "automation_account" {
  description = "Automation account running the start/patch schedules (null when enable_auto_start = false)."
  value       = var.enable_auto_start ? azurerm_automation_account.this[0].name : null
}
