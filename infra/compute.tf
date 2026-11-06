# Compute: Windows Server 2025 VM (Trusted Launch, small OS disk, no backups) and its generated admin password.
# Licence is pay-as-you-go (included in the VM price); no Azure Hybrid Benefit.
# Sign-in is the generated local admin password only (no Entra ID login).

resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!@#%^*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_windows_virtual_machine" "this" {
  name                  = local.names.vm
  computer_name         = local.names.vm
  location              = local.location
  resource_group_name   = data.azurerm_resource_group.this.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.this.id]
  timezone              = var.vm_timezone
  tags                  = local.tags

  # Trusted Launch (Secure Boot + vTPM) hardening; requires a Gen2 image.
  secure_boot_enabled = true
  vtpm_enabled        = true

  priority        = var.use_spot ? "Spot" : "Regular"
  eviction_policy = var.use_spot ? "Deallocate" : null
  max_bid_price   = var.use_spot ? -1 : null

  # Ephemeral VM: no backup configured. Small-disk image (30 GiB) grown to os_disk_size_gb.
  os_disk {
    name                 = local.names.osdisk
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.image_sku
    version   = "latest"
  }

  # Managed storage for boot diagnostics (no storage account to pay for).
  boot_diagnostics {}
}
