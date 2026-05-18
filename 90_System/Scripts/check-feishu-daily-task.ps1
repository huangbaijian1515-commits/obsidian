param(
    [string]$TaskName = "Obsidian Feishu Minutes Sync"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$logRoot = Join-Path $vaultRoot "90_System\Logs"
$today = Get-Date -Format "yyyy-MM-dd"
$todayLogs = @()
if (Test-Path -LiteralPath $logRoot) {
    $todayLogs = @(Get-ChildItem -LiteralPath $logRoot -Filter "feishu-sync-$today*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -eq $task) {
    Write-Host "Task exists: false"
    Write-Host "TaskName: $TaskName"
} else {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
    Write-Host "Task exists: true"
    Write-Host "TaskName: $($task.TaskName)"
    Write-Host "State: $($task.State)"
    Write-Host "LastRunTime: $($info.LastRunTime)"
    Write-Host "LastTaskResult: $($info.LastTaskResult)"
    Write-Host "NextRunTime: $($info.NextRunTime)"
    Write-Host "Execute: $($task.Actions[0].Execute)"
    Write-Host "Arguments: $($task.Actions[0].Arguments)"
    Write-Host "WorkingDirectory: $($task.Actions[0].WorkingDirectory)"
}

Write-Host "Today: $today"
Write-Host "TodayLogExists: $($todayLogs.Count -gt 0)"
Write-Host "TodayLogCount: $($todayLogs.Count)"
foreach ($log in $todayLogs) {
    Write-Host "TodayLog: $($log.LastWriteTime.ToString('s')) $($log.FullName)"
}
