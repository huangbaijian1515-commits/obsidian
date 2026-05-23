param(
    [string]$TaskName = "Obsidian Feishu WeChat Link Sync",
    [string]$Time = "23:30",
    [string]$ContactName = "",
    [int]$DaysBack = 2,
    [int]$RequestDelayMs = 1500,
    [switch]$SaveWithCodex
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

if ([string]::IsNullOrWhiteSpace($ContactName)) {
    $ContactName = -join @([char]0x9EC4, [char]0x4F70, [char]0x5065)
}

$vaultRoot = Get-VaultRoot
$scriptPath = Join-Path $vaultRoot "90_System\Scripts\sync-feishu-wechat-links.ps1"
$powershell = (Get-Command powershell).Source
$argument = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ContactName `"$ContactName`" -DaysBack $DaysBack -RequestDelayMs $RequestDelayMs"
if ($SaveWithCodex) {
    $argument += " -SaveWithCodex"
}

$action = New-ScheduledTaskAction -Execute $powershell -Argument $argument -WorkingDirectory $vaultRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Read-only Feishu chat link scan into local Obsidian queue." -Force | Out-Null
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop

Write-Host "Scheduled task installed."
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "LastRunTime: $($info.LastRunTime)"
Write-Host "LastTaskResult: $($info.LastTaskResult)"
Write-Host "Execute: $($task.Actions[0].Execute)"
Write-Host "Arguments: $($task.Actions[0].Arguments)"
Write-Host "WorkingDirectory: $($task.Actions[0].WorkingDirectory)"
