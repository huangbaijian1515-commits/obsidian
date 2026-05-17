param(
    [string]$TaskName = "Obsidian Feishu Minutes Sync",
    [string]$Time = "23:30"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$scriptPath = Join-Path $vaultRoot "90_System\Scripts\sync-feishu-minutes.ps1"
$powershell = (Get-Command powershell).Source
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -DaysBack 2"

$action = New-ScheduledTaskAction -Execute $powershell -Argument $argument -WorkingDirectory $vaultRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Read-only Feishu Minutes sync into local Obsidian vault." -Force | Out-Null
Write-Host "Scheduled task installed: $TaskName at $Time"
