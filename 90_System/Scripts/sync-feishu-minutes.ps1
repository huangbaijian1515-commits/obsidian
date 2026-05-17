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
$exportRoot = Join-Path $vaultRoot "10_Sources\Attachments\Feishu\Exports"
New-Item -ItemType Directory -Force -Path $logRoot, $exportRoot | Out-Null

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

function Read-JsonFile {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "JSON file is empty: $Path"
    }
    $json = $text | ConvertFrom-Json
    if ($null -ne $json.ok -and $json.ok -eq $false) {
        $message = Get-PropertyValue -Object $json.error -Names @("message", "type", "hint")
        $hint = Get-PropertyValue -Object $json.error -Names @("hint")
        throw "Feishu API returned ok:false. $message $hint"
    }
    return $json
}

function Join-CommandArguments {
    param([string[]]$CliArgs)

    $quoted = @()
    foreach ($arg in $CliArgs) {
        if ($arg -match '[\s"]') {
            $quoted += '"' + ($arg -replace '"', '\"') + '"'
        } else {
            $quoted += $arg
        }
    }
    return ($quoted -join " ")
}

function Invoke-ReadOnlyCliJson {
    param(
        [string]$Executable,
        [string[]]$CliArgs,
        [string]$StandardInput = ""
    )

    Test-ReadOnlyCommand -Parts (@($Executable) + $CliArgs)

    $command = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Executable is not installed. Run 90_System/Scripts/feishu-probe.ps1 for setup hints."
    }

    $commandLine = "$Executable $(Join-CommandArguments -CliArgs $CliArgs)"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/d /c $commandLine"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = -not [string]::IsNullOrWhiteSpace($StandardInput)
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::Start($psi)
    if ($psi.RedirectStandardInput) {
        $process.StandardInput.Write($StandardInput)
        $process.StandardInput.Close()
    }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "Feishu CLI command failed: $stderr $stdout"
    }
    if ([string]::IsNullOrWhiteSpace($stdout)) {
        throw "Feishu CLI returned empty JSON output. $stderr"
    }

    try {
        $json = $stdout | ConvertFrom-Json
    } catch {
        $preview = $stdout
        if ($preview.Length -gt 500) {
            $preview = $preview.Substring(0, 500)
        }
        throw "Failed to parse Feishu CLI JSON. Command: $commandLine. Output preview: $preview"
    }
    if ($null -ne $json.ok -and $json.ok -eq $false) {
        $message = Get-PropertyValue -Object $json.error -Names @("message", "type", "hint")
        $hint = Get-PropertyValue -Object $json.error -Names @("hint")
        throw "Feishu API returned ok:false. $message $hint"
    }
    return $json
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

    return Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args
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

    return Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args
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
    $args = @("minutes", "minutes", "get", "--as", "user", "--params", "-", "--format", "json")
    Test-ReadOnlyCommand -Parts (@($exe) + $args)
    try {
        return Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args -StandardInput $params
    } catch {
        Write-Host "Warning: Feishu minute detail fetch failed for $MinuteToken. $($_.Exception.Message)"
        return $null
    }
}

function Export-FeishuMinuteMarkdown {
    param(
        [string]$DocToken,
        [string]$Title,
        [string]$NoteDate,
        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($DocToken)) {
        return $null
    }

    $exe = "lark-cli.cmd"
    $safeTitle = ConvertTo-SafeFileName -Text $Title
    $baseName = "$NoteDate`_$safeTitle"
    $outputDir = Join-Path $exportRoot $baseName
    $relativeOutputDir = "10_Sources\Attachments\Feishu\Exports\$baseName"
    $expectedPath = Join-Path $outputDir "$baseName.md"

    if ($DryRun) {
        return [pscustomobject]@{
            path = $expectedPath
            content = ""
            dryRun = $true
        }
    }

    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $args = @("drive", "+export", "--as", "user", "--token", $DocToken, "--doc-type", "docx", "--file-extension", "markdown", "--file-name", $baseName, "--output-dir", $relativeOutputDir, "--overwrite")
    Test-ReadOnlyCommand -Parts (@($exe) + $args)

    $commandLine = "$exe $(Join-CommandArguments -CliArgs $args)"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/d /c $commandLine"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "Feishu minute markdown export failed for doc token $DocToken. $stderr $stdout"
    }

    $markdown = Get-ChildItem -LiteralPath $outputDir -Recurse -File -Filter "*.md" | Select-Object -First 1
    if (-not $markdown) {
        throw "Feishu minute markdown export completed but no markdown file was found in $outputDir. $stdout"
    }

    return [pscustomobject]@{
        path = $markdown.FullName
        content = (Get-Content -LiteralPath $markdown.FullName -Encoding UTF8 -Raw)
        dryRun = $false
    }
}

function Search-FeishuMinuteDocs {
    param([string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) {
        return @()
    }

    $exe = "lark-cli.cmd"
    $queries = @("文字记录：$Query", $Query, "智能纪要：$Query")
    $seen = @{}
    $items = @()

    foreach ($candidateQuery in $queries) {
        $args = @("drive", "+search", "--query", $candidateQuery, "--as", "user", "--format", "json")
        $result = Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args
        $resultItems = @()
        if ($null -ne $result.data.results) {
            $resultItems = @($result.data.results)
        } elseif ($null -ne $result.results) {
            $resultItems = @($result.results)
        }

        $validItems = @($resultItems | Where-Object {
            $_.entity_type -eq "DOC" -and
            $null -ne $_.result_meta -and
            $_.result_meta.doc_types -eq "DOCX" -and
            -not [string]::IsNullOrWhiteSpace($_.result_meta.token)
        })

        foreach ($item in $validItems) {
            $token = "$($item.result_meta.token)"
            if (-not [string]::IsNullOrWhiteSpace($token) -and -not $seen.ContainsKey($token)) {
                $seen[$token] = $true
                $items += $item
            }
        }

        if ($candidateQuery -like "文字记录：*" -and $validItems.Count -gt 0) {
            break
        }
    }

    return @($items)
}

function Get-PlainTitle {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }
    $decoded = [System.Net.WebUtility]::HtmlDecode($Text)
    return ($decoded -replace "<[^>]+>", "").Trim()
}

function Select-FeishuMinuteDoc {
    param(
        [object[]]$Docs,
        [string]$UpdatedAt
    )

    if ($Docs.Count -eq 0) {
        return $null
    }

    $transcriptDocs = @($Docs | Where-Object { (Get-PlainTitle -Text "$($_.title_highlighted)") -like "*文字记录*" })
    if ($transcriptDocs.Count -gt 0) {
        $doc = @($transcriptDocs | Sort-Object @{ Expression = { [int64]($_.result_meta.update_time) }; Descending = $true } | Select-Object -First 1)[0]
        return [pscustomobject]@{
            token = "$($doc.result_meta.token)"
            title = (Get-PlainTitle -Text "$($doc.title_highlighted)")
            section = "Feishu Transcript"
        }
    }

    $summaryDocs = @($Docs | Where-Object { (Get-PlainTitle -Text "$($_.title_highlighted)") -like "*智能纪要*" })
    if ($summaryDocs.Count -gt 0) {
        $doc = @($summaryDocs | Sort-Object @{ Expression = { [int64]($_.result_meta.update_time) }; Descending = $true } | Select-Object -First 1)[0]
        return [pscustomobject]@{
            token = "$($doc.result_meta.token)"
            title = (Get-PlainTitle -Text "$($doc.title_highlighted)")
            section = "Feishu Summary"
        }
    }

    $fallback = @($Docs)[0]
    return [pscustomobject]@{
        token = "$($fallback.result_meta.token)"
        title = (Get-PlainTitle -Text "$($fallback.title_highlighted)")
        section = "Feishu Transcript"
    }
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

function Normalize-Record {
    param([object]$Record)

    if ($null -ne $Record.meta_data) {
        if ($null -ne $Record.meta_data.app_link -and $null -eq $Record.PSObject.Properties["url"]) {
            $Record | Add-Member -NotePropertyName "url" -NotePropertyValue $Record.meta_data.app_link
        }
        if ($null -ne $Record.meta_data.description -and $null -eq $Record.PSObject.Properties["summary"]) {
            $Record | Add-Member -NotePropertyName "summary" -NotePropertyValue $Record.meta_data.description
        }
    }

    if ($null -ne $Record.display_info -and $null -eq $Record.PSObject.Properties["title"]) {
        $display = "$($Record.display_info)"
        $title = ($display -split "\r?\n" | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            $Record | Add-Member -NotePropertyName "title" -NotePropertyValue $title
        }
    }

    return $Record
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
    } elseif ($null -ne $Detail.data.minute) {
        $minute = $Detail.data.minute
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
    $data = Read-JsonFile -Path $InputJson
} elseif (Test-Path -LiteralPath (Join-Path $vaultRoot $ConfigFile)) {
    $data = Invoke-ConfiguredListCommand -Path (Join-Path $vaultRoot $ConfigFile)
} else {
    $data = Invoke-FeishuMinutesSearch -DaysBack $DaysBack
}

$records = ConvertTo-Array -Data $data
$cutoff = (Get-Date).AddDays(-1 * $DaysBack)
$created = 0
$skipped = 0
$placeholders = 0
$untranscribed = 0

foreach ($record in $records) {
    $record = Normalize-Record -Record $record
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
    $noteId = Get-PropertyValue -Object $record -Names @("note_id", "doc_token", "document_token")
    $selectedDocToken = ""
    $selectedDocTitle = ""
    $selectedDocSection = "Feishu Transcript"

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
        $docs = Search-FeishuMinuteDocs -Query $title
        $selectedDoc = Select-FeishuMinuteDoc -Docs $docs -UpdatedAt "$updatedAt"
        if ($null -ne $selectedDoc) {
            $selectedDocToken = $selectedDoc.token
            $selectedDocTitle = $selectedDoc.title
            $selectedDocSection = $selectedDoc.section
        }
    }

    if ([string]::IsNullOrWhiteSpace($transcript) -and -not [string]::IsNullOrWhiteSpace($selectedDocToken)) {
        $export = Export-FeishuMinuteMarkdown -DocToken $selectedDocToken -Title $title -NoteDate $noteDate -DryRun:$DryRun
        $transcriptPath = $export.path
        if ($DryRun) {
            $bodyParts += "Feishu DOCX is available and would be exported as Markdown."
        } else {
            $bodyParts += "## $selectedDocSection"
            $bodyParts += ""
            $bodyParts += "Source DOCX: $selectedDocTitle"
            $bodyParts += ""
            $bodyParts += $export.content
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($transcript)) {
        # Already handled above.
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
            if (-not [string]::IsNullOrWhiteSpace($selectedDocToken)) {
                Write-Host "[dry-run] Would import transcribed minute: $noteDate`_$safeTitle ($id) via DOCX $selectedDocToken [$selectedDocSection] $selectedDocTitle"
            } else {
                Write-Host "[dry-run] Would import transcribed minute: $noteDate`_$safeTitle ($id)"
            }
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
        docToken = $selectedDocToken
        transcriptPath = $transcriptPath
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
