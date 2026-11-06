# 8. Resource group, location and VNet

- Date: 2026-11-06
- Status: Accepted

## Context

The VM is always deployed into a resource group that already exists and is owned outside this configuration (for example, created by a platform team with its own policies, tags and RBAC). OpenTofu must never create or delete it.

The resource group's region is not always where the VM should run (for example, latency, capacity or VM size availability). Azure allows resources to be in a different region from their resource group.

Some environments already have a VNet the VM should join, possibly in a different resource group; others have none.

## Decision

- Take the resource group name as a required input, `resource_group_name`, and read it with the `azurerm_resource_group` data source.
- Deploy every resource into one region: `location` if set, otherwise the resource group's location (`local.location`). Resources are not split across regions, because the NIC, VNet, NSG and public IP must share the VM's region anyway.
- `create_vnet` (default `true`) creates a dedicated VNet (`vnet_address_space`, default `10.0.0.0/24`).
- With `create_vnet = false`, the VNet named by `vnet_name` is read as a data source from `vnet_resource_group_name` (defaults to `resource_group_name`). OpenTofu never creates or deletes it.
- In both cases OpenTofu creates the VM's own subnet (`subnet_address_prefix`, default `10.0.0.0/27`) and attaches the NSG to it and to the NIC. Using an existing subnet is not supported, because its NSG and routes are owned elsewhere and the egress allow-list ([ADR 4](0004-network-security.md)) could not be guaranteed.

## Consequences

- The resource group must exist before `tofu apply`; the plan fails if it does not.
- `tofu destroy` removes only the resources this configuration created. The resource group, an existing VNet (only the subnet is removed) and anything else in them are left in place.
- The deploying identity needs Owner or Role Based Access Control Administrator on the resource group only, not the subscription (for the Automation identity's role assignment). With an existing VNet it also needs rights to create subnets in it (e.g. Network Contributor on the VNet or its resource group).
- Resource group tags, policies and region are controlled by its owner; this configuration only tags the resources it creates.
- When `location` differs from the resource group's region, the resource group's metadata stays in its own region; an outage there can block management operations even if the VM's region is healthy.
- VM size, image and Automation availability depend on the chosen region. Changing `location` replaces every resource, which is acceptable because the VM is ephemeral.
- With an existing VNet, `subnet_address_prefix` must be a free range inside it (Azure rejects overlaps at apply time), and the VNet must be in the deployment region (checked by a postcondition that ignores case and spaces, so `UK South` matches `uksouth`).
- Routes or firewalls on an existing VNet (e.g. a hub firewall via peering and UDRs) can further restrict or redirect traffic; the NSG rules still apply.
