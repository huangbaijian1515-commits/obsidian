param(
    [string]$TaskName = "Obsidian Feishu WeChat Link Sync"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$logRoot = Join-Path $vaultRoot "90_System\Logs"
$statePath = Join-Path $vaultRoot "90_System\State\feishu-wechat-sync-state.json"
$today = Get-Date -Format "yyyy-MM-dd"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Task exists: False"
    Write-Host "TaskName: $TaskName"
    exit 0
}

$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction Stop
$todayLogs = @(Get-ChildItem -LiteralPath $logRoot -Filter "feishu-wechat-sync-$today*.log" -File -ErrorAction SilentlyContinue)

Write-Host "Task exists: True"
Write-Host "TaskName: $($task.TaskName)"
Write-Host "State: $($task.State)"
Write-Host "LastRunTime: $($info.LastRunTime)"
Write-Host "LastTaskResult: $($info.LastTaskResult)"
Write-Host "NextRunTime: $($info.NextRunTime)"
Write-Host "Execute: $($task.Actions[0].Execute)"
Write-Host "Arguments: $($task.Actions[0].Arguments)"
Write-Host "WorkingDirectory: $($task.Actions[0].WorkingDirectory)"
Write-Host "TodayLogCount: $($todayLogs.Count)"
foreach ($log in $todayLogs) {
    Write-Host "TodayLog: $($log.FullName)"
}
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "StatePath: $statePath"
    Write-Host "StateLastRunAt: $($state.lastRunAt)"
    $itemCount = @($state.items.PSObject.Properties).Count
    Write-Host "StateItemCount: $itemCount"
} else {
    Write-Host "StatePath: missing"
}
