param(
    [string]$StartDate = "2023-01-01",

    [string]$EndDate = "",

    [int]$WindowDays = 30,

    [switch]$CreatePlaceholderForUntranscribed,

    [switch]$DryRun,

    [int]$RequestDelayMs = 1500,

    [int]$MaxRetries = 5,

    [int]$RetryBaseSeconds = 30,

    [bool]$ContinueOnItemError = $true
)

$ErrorActionPreference = "Stop"

if ($WindowDays -lt 1) {
    throw "WindowDays must be at least 1."
}

$syncScript = Join-Path $PSScriptRoot "sync-feishu-minutes.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Missing sync script: $syncScript"
}

$start = [datetime]::Parse($StartDate).Date
if ([string]::IsNullOrWhiteSpace($EndDate)) {
    $end = (Get-Date).Date
} else {
    $end = [datetime]::Parse($EndDate).Date
}

if ($start -gt $end) {
    throw "StartDate must be earlier than or equal to EndDate."
}

Write-Host "Feishu history sync started. start=$($start.ToString('yyyy-MM-dd')) end=$($end.ToString('yyyy-MM-dd')) windowDays=$WindowDays dryRun=$DryRun"

$windowStart = $start
$windowCount = 0
while ($windowStart -le $end) {
    $windowEnd = $windowStart.AddDays($WindowDays - 1)
    if ($windowEnd -gt $end) {
        $windowEnd = $end
    }

    $windowCount++
    $windowStartText = $windowStart.ToString("yyyy-MM-dd")
    $windowEndText = $windowEnd.ToString("yyyy-MM-dd")
    Write-Host "Running Feishu window #$windowCount $windowStartText to $windowEndText"

    $params = @{
        StartDate = $windowStartText
        EndDate = $windowEndText
        RequestDelayMs = $RequestDelayMs
        MaxRetries = $MaxRetries
        RetryBaseSeconds = $RetryBaseSeconds
        ContinueOnItemError = $ContinueOnItemError
        DryRun = [bool]$DryRun
        CreatePlaceholderForUntranscribed = [bool]$CreatePlaceholderForUntranscribed
    }

    & $syncScript @params
    if ($LASTEXITCODE -ne 0) {
        throw "Feishu sync failed for window $windowStartText to $windowEndText."
    }

    $windowStart = $windowEnd.AddDays(1)
}

Write-Host "Feishu history sync finished. windows=$windowCount dryRun=$DryRun"
