param(
    [int]$DaysBack = 1,

    [string]$StartDate = "",

    [string]$EndDate = "",

    [string]$InputJson = "",

    [string]$ConfigFile = ".\90_System\Config\feishu-sync.json",

    [switch]$CreatePlaceholderForUntranscribed,

    [switch]$DryRun,

    [int]$RequestDelayMs = 1200,

    [int]$MaxRetries = 5,

    [int]$RetryBaseSeconds = 30,

    [bool]$ContinueOnItemError = $true
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$statePath = Join-Path $vaultRoot "90_System\State\feishu-sync-state.json"
$logRoot = Join-Path $vaultRoot "90_System\Logs"
$exportRoot = Join-Path $vaultRoot "10_Sources\Attachments\Feishu\Exports"
New-Item -ItemType Directory -Force -Path $logRoot, $exportRoot | Out-Null

$forbidden = @("edit", "update", "delete", "remove", "upload", "move", "comment", "write", "patch", "put")
$textRecordLabel = -join @([char]0x6587, [char]0x5B57, [char]0x8BB0, [char]0x5F55)
$smartSummaryLabel = -join @([char]0x667A, [char]0x80FD, [char]0x7EAA, [char]0x8981)
$fullWidthColon = [char]0xFF1A
$script:RequestLogEntries = New-Object System.Collections.Generic.List[string]

function Write-RequestLog {
    param([string]$Message)

    $entry = "$(Get-Date -Format s) $Message"
    $script:RequestLogEntries.Add($entry) | Out-Null
    Write-Host $entry
}

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

function Invoke-NativeCliText {
    param(
        [string]$Executable,
        [string[]]$CliArgs
    )

    Test-ReadOnlyCommand -Parts (@($Executable) + $CliArgs)

    $command = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Executable is not installed. Run 90_System/Scripts/feishu-probe.ps1 for setup hints."
    }

    $previousOutputEncoding = [Console]::OutputEncoding
    $previousInputEncoding = [Console]::InputEncoding
    $previousErrorActionPreference = $ErrorActionPreference
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Executable @CliArgs 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        [Console]::OutputEncoding = $previousOutputEncoding
        [Console]::InputEncoding = $previousInputEncoding
    }

    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        throw "Feishu CLI command failed: $text"
    }
    if ($RequestDelayMs -gt 0) {
        Start-Sleep -Milliseconds $RequestDelayMs
    }
    return $text
}

function Test-RateLimitError {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    return ($Text -match "9499" -or $Text -match "too many request" -or $Text -match "rate limit")
}

function Get-RetryDelaySeconds {
    param([int]$Attempt)

    $delay = $RetryBaseSeconds * [math]::Pow(2, [Math]::Max(0, $Attempt - 1))
    return [int][Math]::Min(300, $delay)
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

    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        $commandLine = "$Executable $(Join-CommandArguments -CliArgs $CliArgs)"
        try {
            Write-RequestLog -Message "feishu_cli attempt=$($attempt + 1) command=$commandLine"
            $stdout = Invoke-NativeCliText -Executable $Executable -CliArgs $CliArgs
            if ([string]::IsNullOrWhiteSpace($stdout)) {
                throw "Feishu CLI returned empty JSON output."
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
                $errorText = "Feishu API returned ok:false. $message $hint"
                if (Test-RateLimitError -Text $errorText) {
                    throw $errorText
                }
                throw $errorText
            }
            return $json
        } catch {
            $errorText = $_.Exception.Message
            if ((Test-RateLimitError -Text $errorText) -and $attempt -lt $MaxRetries) {
                $delaySeconds = Get-RetryDelaySeconds -Attempt ($attempt + 1)
                Write-RequestLog -Message "rate_limited attempt=$($attempt + 1) wait_seconds=$delaySeconds command=$commandLine"
                Start-Sleep -Seconds $delaySeconds
                continue
            }
            throw
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

    return Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args
}

function Invoke-FeishuMinutesSearch {
    param(
        [int]$DaysBack,
        [string]$StartDate = "",
        [string]$EndDate = ""
    )

    $exe = "lark-cli.cmd"
    $command = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$exe is not installed. Run 90_System/Scripts/feishu-probe.ps1 for setup hints."
    }

    if ([string]::IsNullOrWhiteSpace($StartDate)) {
        $start = (Get-Date).AddDays(-1 * $DaysBack).ToString("yyyy-MM-dd")
    } else {
        $start = ([datetime]::Parse($StartDate)).ToString("yyyy-MM-dd")
    }

    if ([string]::IsNullOrWhiteSpace($EndDate)) {
        $end = (Get-Date).ToString("yyyy-MM-dd")
    } else {
        $end = ([datetime]::Parse($EndDate)).ToString("yyyy-MM-dd")
    }

    Write-RequestLog -Message "minutes_search_window start=$start end=$end"
    $pageToken = ""
    $seenTokens = @{}
    $items = @()
    $pageCount = 0

    while ($true) {
        $args = @("minutes", "+search", "--as", "user", "--start", $start, "--end", $end, "--page-size", "30", "--format", "json")
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) {
            $args += @("--page-token", $pageToken)
        }
        Test-ReadOnlyCommand -Parts (@($exe) + $args)

        $page = Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args
        $pageCount++
        if ($null -ne $page.data.items) {
            $items += @($page.data.items)
        } elseif ($null -ne $page.items) {
            $items += @($page.items)
        }

        $hasMore = $false
        if ($null -ne $page.data.has_more) {
            $hasMore = [bool]$page.data.has_more
        } elseif ($null -ne $page.has_more) {
            $hasMore = [bool]$page.has_more
        }

        $nextToken = Get-PropertyValue -Object $page.data -Names @("page_token")
        if ([string]::IsNullOrWhiteSpace($nextToken)) {
            $nextToken = Get-PropertyValue -Object $page -Names @("page_token")
        }

        if (-not $hasMore -or [string]::IsNullOrWhiteSpace($nextToken)) {
            break
        }
        if ($seenTokens.ContainsKey($nextToken)) {
            throw "Feishu minutes pagination returned a repeated page token after $pageCount pages."
        }
        $seenTokens[$nextToken] = $true
        $pageToken = $nextToken
    }

    return [pscustomobject]@{
        ok = $true
        data = [pscustomobject]@{
            items = $items
            page_count = $pageCount
            total = $items.Count
        }
    }
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

    $args = @("api", "GET", "/open-apis/minutes/v1/minutes/$MinuteToken", "--as", "user", "--format", "json")
    Test-ReadOnlyCommand -Parts (@($exe) + $args)
    try {
        return Invoke-ReadOnlyCliJson -Executable $exe -CliArgs $args
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
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-RequestLog -Message "feishu_cli attempt=$($attempt + 1) command=$commandLine"
            $stdout = Invoke-NativeCliText -Executable $exe -CliArgs $args
            break
        } catch {
            $errorText = $_.Exception.Message
            if ((Test-RateLimitError -Text $errorText) -and $attempt -lt $MaxRetries) {
                $delaySeconds = Get-RetryDelaySeconds -Attempt ($attempt + 1)
                Write-RequestLog -Message "rate_limited attempt=$($attempt + 1) wait_seconds=$delaySeconds command=$commandLine"
                Start-Sleep -Seconds $delaySeconds
                continue
            }
            throw
        }
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
    $queries = @("$textRecordLabel$fullWidthColon$Query", $Query, "$smartSummaryLabel$fullWidthColon$Query")
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

        if ($candidateQuery -like "$textRecordLabel$fullWidthColon*" -and $validItems.Count -gt 0) {
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

function Normalize-MatchText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }
    $plain = Get-PlainTitle -Text $Text
    return ($plain.ToLowerInvariant() -replace "[^\p{L}\p{Nd}]+", "")
}

function Select-FeishuMinuteDoc {
    param(
        [object[]]$Docs,
        [string]$MinuteTitle,
        [string]$UpdatedAt
    )

    if ($Docs.Count -eq 0) {
        return $null
    }

    $normalizedMinuteTitle = Normalize-MatchText -Text $MinuteTitle
    $matchingDocs = @($Docs | Where-Object {
        $normalizedDocTitle = Normalize-MatchText -Text "$($_.title_highlighted)"
        -not [string]::IsNullOrWhiteSpace($normalizedMinuteTitle) -and $normalizedDocTitle.Contains($normalizedMinuteTitle)
    })

    if ($matchingDocs.Count -eq 0) {
        return $null
    }

    $transcriptDocs = @($matchingDocs | Where-Object { (Get-PlainTitle -Text "$($_.title_highlighted)") -like ("*{0}*" -f $textRecordLabel) })
    if ($transcriptDocs.Count -gt 0) {
        $doc = @($transcriptDocs | Sort-Object @{ Expression = { [int64]($_.result_meta.update_time) }; Descending = $true } | Select-Object -First 1)[0]
        return [pscustomobject]@{
            token = "$($doc.result_meta.token)"
            title = (Get-PlainTitle -Text "$($doc.title_highlighted)")
            section = "Feishu Transcript"
            kind = "transcript"
        }
    }

    $summaryDocs = @($matchingDocs | Where-Object { (Get-PlainTitle -Text "$($_.title_highlighted)") -like ("*{0}*" -f $smartSummaryLabel) })
    if ($summaryDocs.Count -gt 0) {
        $doc = @($summaryDocs | Sort-Object @{ Expression = { [int64]($_.result_meta.update_time) }; Descending = $true } | Select-Object -First 1)[0]
        return [pscustomobject]@{
            token = "$($doc.result_meta.token)"
            title = (Get-PlainTitle -Text "$($doc.title_highlighted)")
            section = "Feishu Summary"
            kind = "summary"
        }
    }

    $fallback = @($matchingDocs)[0]
    return [pscustomobject]@{
        token = "$($fallback.result_meta.token)"
        title = (Get-PlainTitle -Text "$($fallback.title_highlighted)")
        section = "Feishu Related Document"
        kind = "unknown_doc"
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
    $data = Invoke-FeishuMinutesSearch -DaysBack $DaysBack -StartDate $StartDate -EndDate $EndDate
}

$records = ConvertTo-Array -Data $data
$useExplicitWindow = (-not [string]::IsNullOrWhiteSpace($StartDate)) -or (-not [string]::IsNullOrWhiteSpace($EndDate))
if ($useExplicitWindow) {
    if ([string]::IsNullOrWhiteSpace($StartDate)) {
        $windowStart = [datetime]::MinValue
    } else {
        $windowStart = [datetime]::Parse($StartDate).Date
    }
    if ([string]::IsNullOrWhiteSpace($EndDate)) {
        $windowEnd = (Get-Date).Date
    } else {
        $windowEnd = [datetime]::Parse($EndDate).Date
    }
} else {
    $cutoff = (Get-Date).AddDays(-1 * $DaysBack)
}
$created = 0
$skipped = 0
$placeholders = 0
$untranscribed = 0
$errors = 0

foreach ($record in $records) {
    try {
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
    if ($useExplicitWindow -and ($noteDateTime.Date -lt $windowStart -or $noteDateTime.Date -gt $windowEnd)) {
        $skipped++
        continue
    }
    if (-not $useExplicitWindow -and $DaysBack -gt 0 -and $noteDateTime -lt $cutoff.Date) {
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
    $selectedDocKind = ""
    $transcriptUnavailableReason = ""
    $classificationContent = ""
    $contentKind = "unknown"
    $contentKindConfidence = "low"
    $contentKindReason = "not_classified"

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
        $classificationContent = "$transcript"
    } else {
        $docs = Search-FeishuMinuteDocs -Query $title
        $selectedDoc = Select-FeishuMinuteDoc -Docs $docs -MinuteTitle $title -UpdatedAt "$updatedAt"
        if ($null -ne $selectedDoc) {
            $selectedDocToken = $selectedDoc.token
            $selectedDocTitle = $selectedDoc.title
            $selectedDocSection = $selectedDoc.section
            $selectedDocKind = $selectedDoc.kind
        }
    }

    if ([string]::IsNullOrWhiteSpace($transcript) -and -not [string]::IsNullOrWhiteSpace($selectedDocToken) -and $selectedDocKind -in @("transcript", "summary")) {
        $export = Export-FeishuMinuteMarkdown -DocToken $selectedDocToken -Title $title -NoteDate $noteDate -DryRun:$DryRun
        $transcriptPath = $export.path
        if ($selectedDocKind -eq "summary") {
            $needsTranscription = $true
            $transcriptUnavailableReason = "no_text_record_docx_found"
            $untranscribed++
        }
        if ($DryRun) {
            if ($selectedDocKind -eq "summary") {
                $bodyParts += "Feishu summary DOCX is available and would be exported as Markdown. No text record DOCX was found."
            } else {
                $bodyParts += "Feishu text record DOCX is available and would be exported as Markdown."
            }
        } else {
            $bodyParts += "## $selectedDocSection"
            $bodyParts += ""
            $bodyParts += "Source DOCX: $selectedDocTitle"
            $bodyParts += ""
            $bodyParts += $export.content
        }
        if (-not [string]::IsNullOrWhiteSpace($export.content)) {
            $classificationContent = $export.content
        } elseif (-not [string]::IsNullOrWhiteSpace($summary)) {
            $classificationContent = "$summary"
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($transcript)) {
        # Already handled above.
    } else {
        $needsTranscription = $true
        if ($selectedDocKind -eq "unknown_doc") {
            $transcriptUnavailableReason = "no_text_record_or_summary_docx_found"
        } else {
            $transcriptUnavailableReason = "no_related_docx_found"
        }
        $untranscribed++
        $bodyParts += "No Feishu transcript or AI-readable transcript field was available. This stage does not download recordings or run local transcription."
    }

    $status = if ($selectedDocKind -eq "summary") { "summarized" } elseif ($needsTranscription) { "captured" } else { "transcribed" }
    if ([string]::IsNullOrWhiteSpace($classificationContent)) {
        $classificationContent = $bodyParts -join "`n"
    }
    $classification = Get-FeishuContentKind -Title $title -Content $classificationContent
    $contentKind = $classification.kind
    $contentKindConfidence = $classification.confidence
    $contentKindReason = $classification.reason
    $body = $bodyParts -join "`n"

    if ($needsTranscription -and $selectedDocKind -ne "summary" -and -not $CreatePlaceholderForUntranscribed) {
        Write-Host "Skipping untranscribed minute: $noteDate`_$(ConvertTo-SafeFileName -Text $title) ($id)"
        $skipped++
        continue
    }

    if ($DryRun) {
        $safeTitle = ConvertTo-SafeFileName -Text $title
        if ($needsTranscription) {
            if ($selectedDocKind -eq "summary") {
                Write-Host "[dry-run] Would import summarized minute: $noteDate`_$safeTitle ($id) via DOCX $selectedDocToken [$selectedDocSection] $selectedDocTitle; needs_transcription=true content_kind=$contentKind confidence=$contentKindConfidence"
            } else {
                Write-Host "[dry-run] Would create placeholder: $noteDate`_$safeTitle ($id) content_kind=$contentKind confidence=$contentKindConfidence"
                $placeholders++
            }
        } else {
            if (-not [string]::IsNullOrWhiteSpace($selectedDocToken)) {
                Write-Host "[dry-run] Would import transcribed minute: $noteDate`_$safeTitle ($id) via DOCX $selectedDocToken [$selectedDocSection] $selectedDocTitle content_kind=$contentKind confidence=$contentKindConfidence"
            } else {
                Write-Host "[dry-run] Would import transcribed minute: $noteDate`_$safeTitle ($id) content_kind=$contentKind confidence=$contentKindConfidence"
            }
        }
        $created++
        continue
    }

    $notePath = New-FeishuSourceNote -VaultRoot $vaultRoot -Title $title -SourceDate $sourceDate -FeishuId $id -FeishuUrl $url -UpdatedAt "$updatedAt" -Body $body -TranscriptPath $transcriptPath -NeedsTranscription $needsTranscription -Status $status -TranscriptUnavailableReason $transcriptUnavailableReason -ContentKind $contentKind -ContentKindConfidence $contentKindConfidence -ContentKindReason $contentKindReason

    Add-OrUpdateItem -ItemsObject $state.items -Key $id -Value ([pscustomobject]@{
        title = $title
        updatedAt = "$updatedAt"
        notePath = $notePath
        status = $status
        needsTranscription = $needsTranscription
        mediaPath = ""
        docToken = $selectedDocToken
        docKind = $selectedDocKind
        transcriptPath = $transcriptPath
        transcriptUnavailableReason = $transcriptUnavailableReason
        contentKind = $contentKind
        contentKindConfidence = $contentKindConfidence
        contentKindReason = $contentKindReason
    })
    $created++
    Save-State -State $state -Path $statePath
    } catch {
        $errors++
        $errorId = ""
        try {
            $errorId = Get-PropertyValue -Object $record -Names @("id", "token", "minute_token", "meeting_id", "object_token")
        } catch {
            $errorId = "unknown"
        }
        if ([string]::IsNullOrWhiteSpace($errorId)) {
            $errorId = "unknown"
        }
        $message = "item_error id=$errorId message=$($_.Exception.Message)"
        Write-RequestLog -Message $message
        if (-not $ContinueOnItemError) {
            throw
        }
        continue
    }
}

if (-not $DryRun) {
    Save-State -State $state -Path $statePath
}

$logPath = Join-Path $logRoot "feishu-sync-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
$summaryLine = "created=$created skipped=$skipped placeholders=$placeholders untranscribed=$untranscribed errors=$errors dryRun=$DryRun requestDelayMs=$RequestDelayMs maxRetries=$MaxRetries continueOnItemError=$ContinueOnItemError startDate=$StartDate endDate=$EndDate daysBack=$DaysBack"
@($summaryLine) + $script:RequestLogEntries | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "Feishu sync finished. created=$created skipped=$skipped placeholders=$placeholders untranscribed=$untranscribed errors=$errors dryRun=$DryRun"
Write-Host "Log: $logPath"
