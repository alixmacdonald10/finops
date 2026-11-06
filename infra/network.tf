# Networking: VNet (created, or an existing one when create_vnet = false), the VM's own subnet,
# NSG (RDP from allowed_ip only, outbound allow-list), public IP and NIC.
# Also auto-detects the caller's public IP when allowed_ip is not set.
# See docs/adrs/0008-resource-group-and-vnet.md.

locals {
  allowed_ip = coalesce(var.allowed_ip, try(trimspace(data.http.my_ip[0].response_body), null))

  # Outbound allow-list to Internet; everything else to Internet is denied.
  # 443/53 are spec requirements. 80 is needed for Windows Update, CRL and OCSP checks.
  # 22 is allowed for git over SSH (GitHub, Azure DevOps); toggle via allow_ssh_outbound.
  outbound_rules = merge(
    {
      # "*" = TCP + UDP, so QUIC / HTTP3 on UDP 443 also works.
      "Allow-HTTPS-Out" = { priority = 100, protocol = "*", port = "443" }
      "Allow-DNS-Out"   = { priority = 110, protocol = "*", port = "53" }
      "Allow-HTTP-Out"  = { priority = 120, protocol = "Tcp", port = "80" }
    },
    var.allow_ssh_outbound ? {
      "Allow-SSH-Out" = { priority = 130, protocol = "Tcp", port = "22" }
    } : {}
  )

  # VNet the subnet is created in: the one created here, or an existing one.
  vnet_name = var.create_vnet ? azurerm_virtual_network.this[0].name : data.azurerm_virtual_network.existing[0].name
  vnet_rg   = var.create_vnet ? azurerm_virtual_network.this[0].resource_group_name : data.azurerm_virtual_network.existing[0].resource_group_name

  # Azure KMS endpoints for Windows Server pay-as-you-go activation (azkms.core.windows.net, kms.core.windows.net).
  azure_kms_ips = ["20.118.99.224/32", "40.83.235.53/32", "23.102.135.246/32"]
}

# Auto-detect current public IP (only when allowed_ip not set).
data "http" "my_ip" {
  count = var.allowed_ip == null ? 1 : 0
  url   = "https://api.ipify.org"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", trimspace(self.response_body)))
      error_message = "Public IP auto-detect via api.ipify.org failed or returned an unexpected body; set allowed_ip."
    }
  }
}

resource "azurerm_virtual_network" "this" {
  count = var.create_vnet ? 1 : 0

  name                = local.names.vnet
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

# Existing VNet (create_vnet = false). Not created or deleted by OpenTofu.
data "azurerm_virtual_network" "existing" {
  count = var.create_vnet ? 0 : 1

  name                = var.vnet_name
  resource_group_name = coalesce(var.vnet_resource_group_name, var.resource_group_name)

  lifecycle {
    precondition {
      condition     = var.vnet_name != null
      error_message = "vnet_name is required when create_vnet = false."
    }
    postcondition {
      condition     = lower(replace(self.location, " ", "")) == lower(replace(local.location, " ", ""))
      error_message = "The existing VNet must be in the deployment region (location, or the resource group's region if unset); NIC and VNet must share a region."
    }
  }
}

# The VM always gets its own subnet so the NSG (and its egress allow-list) applies to it.
resource "azurerm_subnet" "this" {
  name                 = local.names.snet
  resource_group_name  = local.vnet_rg
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.subnet_address_prefix]
}

resource "azurerm_network_security_group" "this" {
  name                = local.names.nsg
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags

  security_rule {
    name                       = "Allow-RDP-MyIP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*" # RDP uses TCP + UDP 3389
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "${local.allowed_ip}/32"
    destination_address_prefix = "*"
  }

  # Default Azure rules already deny all other inbound from Internet.

  dynamic "security_rule" {
    for_each = local.outbound_rules
    content {
      name                   = security_rule.key
      priority               = security_rule.value.priority
      direction              = "Outbound"
      access                 = "Allow"
      protocol               = security_rule.value.protocol
      source_port_range      = "*"
      destination_port_range = security_rule.value.port
      source_address_prefix  = "*"
      # Requires Internet egress on 443 (HTTPS), 53 (DNS), 80 (Windows Update / CRL / OCSP)
      # and 22 (git over SSH, toggle allow_ssh_outbound). Only these ports are allowed;
      # all other Internet egress is denied by Deny-Internet-Out.
      #trivy:ignore:AZU-0051
      destination_address_prefix = "Internet"
    }
  }

  # Windows Server licence activation; scoped to Azure KMS IPs only.
  security_rule {
    name                         = "Allow-KMS-Out"
    priority                     = 140
    direction                    = "Outbound"
    access                       = "Allow"
    protocol                     = "Tcp"
    source_port_range            = "*"
    destination_port_range       = "1688"
    source_address_prefix        = "*"
    destination_address_prefixes = local.azure_kms_ips
  }

  # Platform traffic (168.63.129.16: Azure DNS, VM agent) is not affected by NSG rules.
  security_rule {
    name                       = "Deny-Internet-Out"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_public_ip" "this" {
  name                = local.names.pip
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard" # Basic SKU retired
  tags                = local.tags
}

resource "azurerm_network_interface" "this" {
  name                = local.names.nic
  location            = local.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    # Public IP is required for direct RDP; access is locked to allowed_ip by the NSG.
    # Azure Bastion would remove it but costs far more than this VM.
    #trivy:ignore:AZU-0076
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

# NSG on NIC as well as subnet (defence in depth, satisfies trivy AZU-0068).
resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}
