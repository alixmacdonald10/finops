# Schedules: daily DevTest auto-shutdown at end of day, plus an Automation account + runbook that
# starts the VM on weekdays and keeps it on for the Sunday 01:00 patch window.
# Patches are installed by in-guest Windows Update (scripts/setup.ps1) during this window.
# The Automation identity's role assignment lives in iam.tf.

locals {
  # Schedules must start in the future; time-of-day is taken from start_time. Use tomorrow, or
  # Monday if tomorrow is Sunday, so the first run date is never a UK clock-change day.
  schedule_base = timeadd(timestamp(), "24h")
  schedule_ts   = formatdate("EEE", local.schedule_base) == "Sun" ? timeadd(local.schedule_base, "24h") : local.schedule_base
  schedule_date = formatdate("YYYY-MM-DD", local.schedule_ts)
  schedule_year = formatdate("YYYY", local.schedule_ts)

  # Europe/London: BST runs from the last Sunday of March to the last Sunday of October.
  # start_time must carry the correct UTC offset for its date; Azure then keeps wall-clock time across DST.
  weekday_index = { Sun = 0, Mon = 1, Tue = 2, Wed = 3, Thu = 4, Fri = 5, Sat = 6 }
  bst_start_day = 31 - local.weekday_index[formatdate("EEE", "${local.schedule_year}-03-31T00:00:00Z")]
  bst_end_day   = 31 - local.weekday_index[formatdate("EEE", "${local.schedule_year}-10-31T00:00:00Z")]
  schedule_mmdd = tonumber(formatdate("MMDD", local.schedule_ts))
  is_bst        = local.schedule_mmdd > 300 + local.bst_start_day && local.schedule_mmdd < 1000 + local.bst_end_day
  utc_offset    = local.is_bst ? "+01:00" : "+00:00"

  schedules = var.enable_auto_start ? {
    weekday-start = {
      time   = var.work_start_time
      days   = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      action = "start"
    }
    patch-start = {
      time   = var.patch_window_start
      days   = ["Sunday"]
      action = "start"
    }
    patch-stop = {
      time   = var.patch_window_stop
      days   = ["Sunday"]
      action = "stop"
    }
  } : {}
}

# Daily deallocate at end of the UK working day (uses the VM's Windows timezone, GMT Standard Time = UK with DST).
resource "azurerm_dev_test_global_vm_shutdown_schedule" "this" {
  count = var.auto_shutdown_time == null ? 0 : 1

  virtual_machine_id    = azurerm_windows_virtual_machine.this.id
  location              = local.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.vm_timezone
  tags                  = local.tags

  notification_settings {
    enabled = false
  }
}

resource "azurerm_automation_account" "this" {
  count = var.enable_auto_start ? 1 : 0

  name                         = local.names.aa
  location                     = local.location
  resource_group_name          = data.azurerm_resource_group.this.name
  sku_name                     = "Basic"
  local_authentication_enabled = false
  tags                         = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_runtime_environment" "ps74" {
  count = var.enable_auto_start ? 1 : 0

  name                  = "powershell-7-4"
  location              = local.location
  automation_account_id = azurerm_automation_account.this[0].id
  runtime_language      = "PowerShell"
  runtime_version       = "7.4"
  description           = "PowerShell 7.4 runtime for the vm-power runbook."
  # Azure allows at most 3 tags on a runtime environment; use only the base tags.
  tags = local.base_tags

  # Az default package offered for PowerShell 7.4; bump when Azure deprecates it.
  runtime_default_packages = {
    Az = "12.3.0"
  }
}

resource "azurerm_automation_runbook" "vm_power" {
  count = var.enable_auto_start ? 1 : 0

  name                     = "vm-power"
  location                 = local.location
  resource_group_name      = data.azurerm_resource_group.this.name
  automation_account_name  = azurerm_automation_account.this[0].name
  runbook_type             = "PowerShell"
  runtime_environment_name = azurerm_automation_runtime_environment.ps74[0].name
  log_verbose              = false
  log_progress             = false
  description              = "Start or deallocate the dev VM."
  tags                     = local.tags

  content = <<-PS
    param(
      [Parameter(Mandatory)][ValidateSet('start', 'stop')][string]$Action,
      [Parameter(Mandatory)][string]$ResourceGroupName,
      [Parameter(Mandatory)][string]$VMName
    )
    $ErrorActionPreference = 'Stop'
    Connect-AzAccount -Identity | Out-Null
    if ($Action -eq 'start') {
      Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName | Out-Null
    } else {
      # Only deallocate when the VM is actually running; skip if already stopped/deallocated.
      $power = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status).Statuses |
        Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -ExpandProperty Code
      if ($power -ne 'PowerState/running') {
        Write-Output "$VMName is $power; nothing to stop"
        return
      }
      Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force | Out-Null
    }
    Write-Output "$Action completed for $VMName"
  PS
}

resource "azurerm_automation_schedule" "this" {
  for_each = local.schedules

  name                    = each.key
  resource_group_name     = data.azurerm_resource_group.this.name
  automation_account_name = azurerm_automation_account.this[0].name
  frequency               = "Week"
  interval                = 1
  week_days               = each.value.days
  timezone                = "Europe/London"
  start_time              = "${local.schedule_date}T${each.value.time}:00${local.utc_offset}"

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "this" {
  for_each = local.schedules

  resource_group_name     = data.azurerm_resource_group.this.name
  automation_account_name = azurerm_automation_account.this[0].name
  schedule_name           = azurerm_automation_schedule.this[each.key].name
  runbook_name            = azurerm_automation_runbook.vm_power[0].name

  # Keys must be lowercase; PowerShell parameter binding is case-insensitive.
  parameters = {
    action            = each.value.action
    resourcegroupname = data.azurerm_resource_group.this.name
    vmname            = azurerm_windows_virtual_machine.this.name
  }

  depends_on = [azurerm_role_assignment.automation_vm]
}
