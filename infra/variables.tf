# Input variables: target resource group, naming, VM sizing and image, UK working-hours / Sunday patch schedules,
# access (allowed IP) and outbound toggles. Real values go in terraform.tfvars (gitignored).

variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID env var."
  type        = string
  default     = null
}

variable "project" {
  description = "Project name used in resource names: <resource>-<project>-<environment>."
  type        = string
  default     = "devvm"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.project))
    error_message = "project must be 2-8 lowercase alphanumeric chars (Windows computer name limit is 15)."
  }
}

variable "environment" {
  description = "Environment name, e.g. dev, test, prod."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,4}$", var.environment))
    error_message = "environment must be 2-4 lowercase alphanumeric chars."
  }
}

variable "resource_group_name" {
  description = "Name of the pre-existing resource group to deploy into. Not created or deleted by OpenTofu; resources use its location unless location is set."
  type        = string
}

variable "location" {
  description = "Azure region for all resources (e.g. uksouth). May differ from the resource group's region. Defaults to the resource group's location when null."
  type        = string
  default     = null
}

variable "create_vnet" {
  description = "Create a dedicated VNet. Set false to create the VM's subnet in an existing VNet (vnet_name)."
  type        = bool
  default     = true
}

variable "vnet_name" {
  description = "Existing VNet to create the subnet in. Required when create_vnet = false; ignored otherwise."
  type        = string
  default     = null
}

variable "vnet_resource_group_name" {
  description = "Resource group of the existing VNet. Defaults to resource_group_name. Ignored when create_vnet = true."
  type        = string
  default     = null
}

variable "vnet_address_space" {
  description = "Address space of the created VNet. Ignored when create_vnet = false."
  type        = list(string)
  default     = ["10.0.0.0/24"]

  validation {
    condition     = alltrue([for c in var.vnet_address_space : can(cidrhost(c, 0))])
    error_message = "vnet_address_space entries must be valid CIDRs."
  }
}

variable "subnet_address_prefix" {
  description = "CIDR of the VM's subnet. Must sit inside the VNet and, for an existing VNet, not overlap other subnets (a /28 is enough)."
  type        = string
  default     = "10.0.0.0/27"

  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "subnet_address_prefix must be a valid CIDR, e.g. 10.0.0.0/27."
  }
}

variable "admin_username" {
  description = "Local admin username for RDP login."
  type        = string
}

variable "allowed_ip" {
  description = "Single public IPv4 address allowed to RDP (no CIDR; /32 is added). Leave null to auto-detect your current IP."
  type        = string
  default     = null

  validation {
    condition     = var.allowed_ip == null || can(cidrhost("${var.allowed_ip}/32", 0)) && can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.allowed_ip))
    error_message = "allowed_ip must be a single IPv4 address like 203.0.113.10 (no CIDR suffix)."
  }
}

variable "vm_size" {
  description = "VM size. B2als_v2 = 2 vCPU / 4 GiB, cheapest burstable size that runs Windows Server with Desktop Experience and Trusted Launch."
  type        = string
  default     = "Standard_B2als_v2"
}

variable "os_disk_type" {
  description = "OS disk SKU. Standard_LRS (HDD) cheapest; StandardSSD_LRS noticeably snappier for a few £ more."
  type        = string
  default     = "Standard_LRS"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB. Small-disk image is 30 GiB, which leaves little room for updates; 64 GiB is still a small, cheap tier."
  type        = number
  default     = 64

  validation {
    condition     = var.os_disk_size_gb >= 30 && var.os_disk_size_gb <= 127
    error_message = "os_disk_size_gb must be between 30 and 127."
  }
}

variable "image_sku" {
  description = "Windows Server image SKU (publisher MicrosoftWindowsServer, offer WindowsServer). Must be a Gen2 image for Trusted Launch. Licence is pay-as-you-go."
  type        = string
  default     = "2025-datacenter-smalldisk-g2"
}

variable "use_spot" {
  description = "Run as Spot VM (much cheaper, can be evicted at any time - VM is deallocated, disk kept)."
  type        = bool
  default     = false
}

variable "auto_shutdown_time" {
  description = "Daily auto-shutdown (deallocate) time, HHMM 24h, end of UK working day, in vm_timezone. Null disables it, which breaks the AGENTS.md cost requirement."
  type        = string
  default     = "1700"

  validation {
    condition     = var.auto_shutdown_time == null || can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "auto_shutdown_time must be HHMM 24h, e.g. 1700."
  }
}

variable "vm_timezone" {
  description = "Windows timezone ID set inside the VM and used for auto-shutdown. GMT Standard Time = UK time with BST."
  type        = string
  default     = "GMT Standard Time"
}

variable "enable_auto_start" {
  description = "Create an Automation account that starts the VM on weekdays and runs the Sunday patch window (Europe/London)."
  type        = bool
  default     = true
}

variable "work_start_time" {
  description = "Weekday (Mon-Fri) auto-start time, HH:MM 24h, Europe/London."
  type        = string
  default     = "08:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.work_start_time))
    error_message = "work_start_time must be HH:MM 24h, e.g. 08:00."
  }
}

variable "patch_window_start" {
  description = "Sunday start time so in-guest Windows Update can install at 01:00, HH:MM 24h, Europe/London."
  type        = string
  default     = "00:45"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.patch_window_start))
    error_message = "patch_window_start must be HH:MM 24h, e.g. 00:45."
  }
}

variable "patch_window_stop" {
  description = "Sunday deallocate time after patching, HH:MM 24h, Europe/London."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.patch_window_stop))
    error_message = "patch_window_stop must be HH:MM 24h, e.g. 03:00."
  }
}

variable "allow_ssh_outbound" {
  description = "Allow outbound TCP 22 for git over SSH (GitHub, Azure DevOps). Set false to block."
  type        = bool
  default     = true
}

variable "neovim_version" {
  description = "Neovim release tag installed from GitHub releases."
  type        = string
  default     = "v0.12.6"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.neovim_version))
    error_message = "neovim_version must be a release tag like v0.12.6."
  }
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
