param(
    [int]$DaysBack = 1,

    [string]$InputJson = "",

    [string]$ConfigFile = ".\90_System\Config\feishu-sync.json",

    [switch]$CreatePlaceholderForUntranscribed,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$statePath = Join-Path $vaultRoot "90_System\State\feishu-sync-state.json"
$logRoot = Join-Path $vaultRoot "90_System\Logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

trap {
    $errorLogPath = Join-Path $logRoot "feishu-sync-error-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
    ($_ | Out-String) | Set-Content -LiteralPath $errorLogPath -Encoding UTF8
    Write-Error "Feishu sync failed. Error log: $errorLogPath"
    exit 1
}

$forbidden = @("edit", "update", "delete", "remove", "upload", "move", "comment", "write", "patch", "put")

function Read-State {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            version = 1
            lastRunAt = ""
            items = [pscustomobject]@{}
        }
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Save-State {
    param(
        [object]$State,
        [string]$Path
    )
    $State.lastRunAt = (Get-Date).ToString("s")
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        if ($null -ne $Object.PSObject.Properties[$name]) {
            $value = $Object.$name
            if ($null -ne $value -and "$value" -ne "") {
                return $value
            }
        }
    }
    return ""
}

function Test-ReadOnlyCommand {
    param([string[]]$Parts)

    $joined = ($Parts -join " ").ToLowerInvariant()
    foreach ($word in $forbidden) {
        if ($joined -match "(^|\s|/|--)$word($|\s|/|-)") {
            throw "Refusing to run non-read-only Feishu command because it contains forbidden operation '$word': $joined"
        }
    }
}

function Invoke-ConfiguredListCommand {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No InputJson provided and config not found: $Path. Copy 90_System/Config/feishu-sync.example.json to feishu-sync.json after running feishu-probe.ps1."
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.readOnly -ne $true) {
        throw "Config must contain readOnly: true."
    }

    $exe = $config.minutesListCommand.executable
    $args = @($config.minutesListCommand.args)
    Test-ReadOnlyCommand -Parts (@($exe) + $args)

    $command = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$exe is not installed. Run 90_System/Scripts/feishu-probe.ps1 for setup hints."
    }

    $output = & $exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "Feishu list command failed."
    }
    return ($output -join "`n")
}

function Invoke-FeishuMinutesSearch {
    param([int]$DaysBack)

    $exe = "lark-cli.cmd"
    $command = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$exe is not installed. Run 90_System/Scripts/feishu-probe.ps1 for setup hints."
    }

    $start = (Get-Date).AddDays(-1 * $DaysBack).ToString("yyyy-MM-dd")
    $end = (Get-Date).ToString("yyyy-MM-dd")
    $args = @("minutes", "+search", "--as", "user", "--start", $start, "--end", $end, "--page-size", "30", "--format", "json")
    Test-ReadOnlyCommand -Parts (@($exe) + $args)

    $output = & $exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "Feishu minutes search failed."
    }
    return ($output -join "`n")
}

function Invoke-FeishuMinuteGet {
    param([string]$MinuteToken)

    if ([string]::IsNullOrWhiteSpace($MinuteToken)) {
        return $null
    }

    $exe = "lark-cli.cmd"
    $command = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$exe is not installed. Run 90_System/Scripts/feishu-probe.ps1 for setup hints."
    }

    $params = @{ minute_token = $MinuteToken; user_id_type = "open_id" } | ConvertTo-Json -Compress
    $args = @("minutes", "minutes", "get", "--as", "user", "--params", $params, "--format", "json")
    Test-ReadOnlyCommand -Parts (@($exe) + $args)

    $output = & $exe @args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: Feishu minute detail fetch failed for $MinuteToken"
        return $null
    }
    $text = $output -join "`n"
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    return ($text | ConvertFrom-Json)
}

function ConvertTo-Array {
    param([object]$Data)

    if ($Data -is [System.Array]) {
        return @($Data)
    }
    if ($null -ne $Data.items) {
        return @($Data.items)
    }
    if ($null -ne $Data.data.items) {
        return @($Data.data.items)
    }
    if ($null -ne $Data.minutes) {
        return @($Data.minutes)
    }
    return @($Data)
}

function Add-OrUpdateItem {
    param(
        [object]$ItemsObject,
        [string]$Key,
        [object]$Value
    )
    if ($null -eq $ItemsObject.PSObject.Properties[$Key]) {
        $ItemsObject | Add-Member -NotePropertyName $Key -NotePropertyValue $Value
    } else {
        $ItemsObject.$Key = $Value
    }
}

function Merge-RecordWithDetail {
    param(
        [object]$Record,
        [object]$Detail
    )

    if ($null -eq $Detail) {
        return $Record
    }

    $minute = $Detail
    if ($null -ne $Detail.minute) {
        $minute = $Detail.minute
    }

    foreach ($property in $minute.PSObject.Properties) {
        if ($null -eq $Record.PSObject.Properties[$property.Name]) {
            $Record | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        } elseif ([string]::IsNullOrWhiteSpace("$($Record.$($property.Name))")) {
            $Record.$($property.Name) = $property.Value
        }
    }

    return $Record
}

$state = Read-State -Path $statePath
$jsonText = ""
if (-not [string]::IsNullOrWhiteSpace($InputJson)) {
    $jsonText = Get-Content -LiteralPath $InputJson -Raw
} elseif (Test-Path -LiteralPath (Join-Path $vaultRoot $ConfigFile)) {
    $jsonText = Invoke-ConfiguredListCommand -Path (Join-Path $vaultRoot $ConfigFile)
} else {
    $jsonText = Invoke-FeishuMinutesSearch -DaysBack $DaysBack
}

$data = $jsonText | ConvertFrom-Json
$records = ConvertTo-Array -Data $data
$cutoff = (Get-Date).AddDays(-1 * $DaysBack)
$created = 0
$skipped = 0
$placeholders = 0
$untranscribed = 0

foreach ($record in $records) {
    $id = Get-PropertyValue -Object $record -Names @("id", "token", "minute_token", "meeting_id", "object_token")
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = [guid]::NewGuid().ToString()
    }

    if ([string]::IsNullOrWhiteSpace($InputJson)) {
        $detail = Invoke-FeishuMinuteGet -MinuteToken $id
        $record = Merge-RecordWithDetail -Record $record -Detail $detail
    }

    $title = Get-PropertyValue -Object $record -Names @("title", "name", "topic", "meeting_topic")
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = "Feishu Minutes $id"
    }

    $updatedAt = Get-PropertyValue -Object $record -Names @("updated_at", "update_time", "modified_at", "modified_time")
    $sourceDate = Get-PropertyValue -Object $record -Names @("date", "start_time", "created_at", "create_time", "meeting_start_time")
    $noteDate = ConvertTo-NoteDate -Value $sourceDate
    $noteDateTime = [datetime]::Parse($noteDate)
    if ($DaysBack -gt 0 -and $noteDateTime -lt $cutoff.Date) {
        $skipped++
        continue
    }

    $existing = $state.items.PSObject.Properties[$id]
    if ($null -ne $existing -and $existing.Value.updatedAt -eq "$updatedAt") {
        $skipped++
        continue
    }

    $url = Get-PropertyValue -Object $record -Names @("url", "share_url", "link")
    $summary = Get-PropertyValue -Object $record -Names @("summary", "abstract", "ai_summary")
    $transcript = Get-PropertyValue -Object $record -Names @("transcript", "transcript_text", "content", "text", "minutes", "plain_text", "paragraphs")
    $actions = Get-PropertyValue -Object $record -Names @("action_items", "todo", "tasks")

    $bodyParts = @()
    if (-not [string]::IsNullOrWhiteSpace($summary)) {
        $bodyParts += "## Feishu Summary"
        $bodyParts += ""
        $bodyParts += "$summary"
        $bodyParts += ""
    }
    if (-not [string]::IsNullOrWhiteSpace($actions)) {
        $bodyParts += "## Feishu Action Items"
        $bodyParts += ""
        $bodyParts += "$actions"
        $bodyParts += ""
    }

    $needsTranscription = $false
    $transcriptPath = ""
    if (-not [string]::IsNullOrWhiteSpace($transcript)) {
        $bodyParts += "## Feishu Transcript"
        $bodyParts += ""
        $bodyParts += "$transcript"
    } else {
        $needsTranscription = $true
        $untranscribed++
        $bodyParts += "No Feishu transcript or AI-readable transcript field was available. This stage does not download recordings or run local transcription."
    }

    $status = if ($needsTranscription) { "captured" } else { "transcribed" }
    $body = $bodyParts -join "`n"

    if ($needsTranscription -and -not $CreatePlaceholderForUntranscribed) {
        Write-Host "Skipping untranscribed minute: $noteDate`_$(ConvertTo-SafeFileName -Text $title) ($id)"
        $skipped++
        continue
    }

    if ($DryRun) {
        $safeTitle = ConvertTo-SafeFileName -Text $title
        if ($needsTranscription) {
            Write-Host "[dry-run] Would create placeholder: $noteDate`_$safeTitle ($id)"
            $placeholders++
        } else {
            Write-Host "[dry-run] Would import transcribed minute: $noteDate`_$safeTitle ($id)"
        }
        $created++
        continue
    }

    $notePath = New-FeishuSourceNote -VaultRoot $vaultRoot -Title $title -SourceDate $sourceDate -FeishuId $id -FeishuUrl $url -UpdatedAt "$updatedAt" -Body $body -TranscriptPath $transcriptPath -NeedsTranscription $needsTranscription -Status $status

    Add-OrUpdateItem -ItemsObject $state.items -Key $id -Value ([pscustomobject]@{
        title = $title
        updatedAt = "$updatedAt"
        notePath = $notePath
        status = $status
        needsTranscription = $needsTranscription
        mediaPath = ""
    })
    $created++
}

if (-not $DryRun) {
    Save-State -State $state -Path $statePath
}

$logPath = Join-Path $logRoot "feishu-sync-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
"created=$created skipped=$skipped placeholders=$placeholders untranscribed=$untranscribed dryRun=$DryRun" | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "Feishu sync finished. created=$created skipped=$skipped placeholders=$placeholders untranscribed=$untranscribed dryRun=$DryRun"
Write-Host "Log: $logPath"
