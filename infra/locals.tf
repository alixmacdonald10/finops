# Shared locals: resource naming convention and common tags.
# Component-specific locals live in the file that uses them (network.tf, automation.tf).

locals {
  suffix = "${var.project}-${var.environment}"

  # Naming convention: <resource>-<project>-<environment>
  names = {
    vnet   = "vnet-${local.suffix}"
    snet   = "snet-${local.suffix}"
    nsg    = "nsg-${local.suffix}"
    pip    = "pip-${local.suffix}"
    nic    = "nic-${local.suffix}"
    vm     = "vm-${local.suffix}"
    osdisk = "osdisk-${local.suffix}"
    aa     = "aa-${local.suffix}"
  }

  base_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "opentofu"
  }

  tags = merge(local.base_tags, var.tags)
}
