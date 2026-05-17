param(
    [int]$DaysBack = 1,

    [string]$InputJson = "",

    [string]$ConfigFile = ".\90_System\Config\feishu-sync.json",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$statePath = Join-Path $vaultRoot "90_System\State\feishu-sync-state.json"
$attachmentRoot = Join-Path $vaultRoot "10_Sources\Attachments\Feishu"
$logRoot = Join-Path $vaultRoot "90_System\Logs"
New-Item -ItemType Directory -Force -Path $attachmentRoot, $logRoot | Out-Null

trap {
    $errorLogPath = Join-Path $logRoot "feishu-sync-error-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
    ($_ | Out-String) | Set-Content -LiteralPath $errorLogPath -Encoding UTF8
    Write-Error "Feishu sync failed. Error log: $errorLogPath"
    exit 1
}

$forbidden = @("edit", "update", "delete", "remove", "upload", "move", "comment", "write", "patch", "post", "put")

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

$state = Read-State -Path $statePath
$jsonText = ""
if (-not [string]::IsNullOrWhiteSpace($InputJson)) {
    $jsonText = Get-Content -LiteralPath $InputJson -Raw
} else {
    $jsonText = Invoke-ConfiguredListCommand -Path (Join-Path $vaultRoot $ConfigFile)
}

$data = $jsonText | ConvertFrom-Json
$records = ConvertTo-Array -Data $data
$cutoff = (Get-Date).AddDays(-1 * $DaysBack)
$created = 0
$skipped = 0

foreach ($record in $records) {
    $id = Get-PropertyValue -Object $record -Names @("id", "token", "minute_token", "meeting_id", "object_token")
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = [guid]::NewGuid().ToString()
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
    $transcript = Get-PropertyValue -Object $record -Names @("transcript", "transcript_text", "content", "text", "minutes")
    $actions = Get-PropertyValue -Object $record -Names @("action_items", "todo", "tasks")
    $mediaPath = Get-PropertyValue -Object $record -Names @("media_path", "recording_path", "audio_path", "video_path")
    $mediaUrl = Get-PropertyValue -Object $record -Names @("media_url", "recording_url", "download_url")

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
    } elseif (-not [string]::IsNullOrWhiteSpace($mediaPath) -and (Test-Path -LiteralPath $mediaPath)) {
        $safeTitle = ConvertTo-SafeFileName -Text $title
        $transcriptPath = Join-Path $attachmentRoot "$noteDate`_$safeTitle.transcript.md"
        if (-not $DryRun) {
            & "$PSScriptRoot\transcribe-local.ps1" -MediaFile $mediaPath -OutputFile $transcriptPath
        }
        $bodyParts += "## Local Transcript"
        $bodyParts += ""
        $bodyParts += "Transcript path: $transcriptPath"
    } elseif (-not [string]::IsNullOrWhiteSpace($mediaUrl)) {
        $needsTranscription = $true
        $bodyParts += "Recording URL detected but not downloaded automatically because authenticated Feishu media downloads vary by tenant."
        $bodyParts += ""
        $bodyParts += "Recording URL: $mediaUrl"
    } else {
        $needsTranscription = $true
        $bodyParts += "No Feishu transcript or local recording was available. Add media and run transcribe-local.ps1."
    }

    $status = if ($needsTranscription) { "captured" } else { "transcribed" }
    $body = $bodyParts -join "`n"

    if ($DryRun) {
        $safeTitle = ConvertTo-SafeFileName -Text $title
        Write-Host "[dry-run] Would import: $noteDate`_$safeTitle ($id)"
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
        mediaPath = $mediaPath
    })
    $created++
}

if (-not $DryRun) {
    Save-State -State $state -Path $statePath
}

$logPath = Join-Path $logRoot "feishu-sync-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
"created=$created skipped=$skipped dryRun=$DryRun" | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "Feishu sync finished. created=$created skipped=$skipped dryRun=$DryRun"
Write-Host "Log: $logPath"
