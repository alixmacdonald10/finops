# Pre-existing resource group that holds every resource in this deployment. It is not created or
# destroyed by OpenTofu. Resources are deployed into var.location, or the resource group's
# location when unset.
# See docs/adrs/0008-resource-group-and-vnet.md.

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  # Region for every resource; may differ from the resource group's region.
  location = coalesce(var.location, data.azurerm_resource_group.this.location)
}
