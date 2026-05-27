param(
    [string]$ContactName = "",
    [int]$DaysBack = 2,
    [string]$Start = "",
    [string]$End = "",
    [int]$PageSize = 50,
    [int]$RequestDelayMs = 1500,
    [int]$MaxRetries = 5,
    [int]$RetryBaseSeconds = 30,
    [switch]$DryRun,
    [switch]$SaveWithCodex
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

if ([string]::IsNullOrWhiteSpace($ContactName)) {
    $ContactName = -join @([char]0x9EC4, [char]0x4F70, [char]0x5065)
}

$vaultRoot = Get-VaultRoot
$statePath = Join-Path $vaultRoot "90_System\State\feishu-wechat-sync-state.json"
$logRoot = Join-Path $vaultRoot "90_System\Logs"
$queueRoot = Join-Path $vaultRoot "90_System\Queue\Wechat"
$wechatRoot = Join-Path $vaultRoot "10_Sources\Wechat"
New-Item -ItemType Directory -Force -Path $logRoot, $queueRoot, $wechatRoot | Out-Null

$script:RequestLogEntries = New-Object System.Collections.Generic.List[string]
$forbiddenFeishuPatterns = @(
    '(\s|^)send($|\s|-)',
    '(\s|^)reply($|\s|-)',
    '(\s|^)create($|\s|-)',
    '(\s|^)update($|\s|-)',
    '(\s|^)delete($|\s|-)',
    '(\s|^)patch($|\s|-)',
    '(\s|^)put($|\s|-)',
    ("\+" + "upload"),
    ("\+" + "download")
)

function Write-RequestLog {
    param([string]$Message)
    $entry = "$(Get-Date -Format s) $Message"
    $script:RequestLogEntries.Add($entry) | Out-Null
    Write-Host $entry
}

trap {
    $fatalLogPath = Join-Path $logRoot "feishu-wechat-sync-error-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
    @("fatal_error=$($_.Exception.Message)") + $script:RequestLogEntries | Set-Content -LiteralPath $fatalLogPath -Encoding UTF8
    Write-Error "Feishu WeChat sync failed. Error log: $fatalLogPath"
    exit 1
}

function Read-State {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            version = 1
            lastRunAt = ""
            contactName = ""
            contactOpenId = ""
            items = [pscustomobject]@{}
        }
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-State {
    param(
        [object]$State,
        [string]$Path
    )
    $State.lastRunAt = (Get-Date).ToString("s")
    $State | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )
    if ($null -eq $Object) {
        return ""
    }
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

function Get-StableId {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
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

function Test-ReadOnlyFeishuCommand {
    param([string[]]$Parts)
    $joined = ($Parts -join " ").ToLowerInvariant()
    foreach ($pattern in $forbiddenFeishuPatterns) {
        if ($joined -match $pattern) {
            throw "Refusing to run a non-read-only Feishu command: $joined"
        }
    }
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
        [string[]]$CliArgs
    )

    Test-ReadOnlyFeishuCommand -Parts (@($Executable) + $CliArgs)
    $command = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Executable is not installed or not on PATH."
    }

    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        $commandLine = "$Executable $(Join-CommandArguments -CliArgs $CliArgs)"
        try {
            Write-RequestLog -Message "feishu_cli attempt=$($attempt + 1) command=$commandLine"
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
            if ([string]::IsNullOrWhiteSpace($text)) {
                throw "Feishu CLI returned empty JSON output."
            }
            $json = $text | ConvertFrom-Json
            if ($null -ne $json.ok -and $json.ok -eq $false) {
                $message = Get-PropertyValue -Object $json.error -Names @("message", "type", "hint")
                throw "Feishu API returned ok:false. $message"
            }
            if ($RequestDelayMs -gt 0) {
                Start-Sleep -Milliseconds $RequestDelayMs
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

function Get-ChildObjects {
    param([object]$Object)
    if ($null -eq $Object) {
        return @()
    }
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        return @($Object)
    }
    return @($Object.PSObject.Properties | ForEach-Object { $_.Value })
}

function Find-ObjectsWithProperty {
    param(
        [object]$Root,
        [string[]]$PropertyNames
    )
    $found = @()
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($null -eq $current) {
            continue
        }
        foreach ($name in $PropertyNames) {
            if ($null -ne $current.PSObject.Properties[$name]) {
                $found += $current
                break
            }
        }
        foreach ($child in (Get-ChildObjects -Object $current)) {
            if ($null -ne $child -and -not ($child -is [string])) {
                $queue.Enqueue($child)
            }
        }
    }
    return $found
}

function Resolve-FeishuContactOpenId {
    param(
        [string]$Name,
        [object]$State
    )
    if ($State.contactName -eq $Name -and -not [string]::IsNullOrWhiteSpace($State.contactOpenId)) {
        return "$($State.contactOpenId)"
    }

    $json = Invoke-ReadOnlyCliJson -Executable "lark-cli.cmd" -CliArgs @("contact", "+search-user", "--query", $Name, "--has-chatted", "--as", "user", "--format", "json")
    $candidates = @(Find-ObjectsWithProperty -Root $json -PropertyNames @("open_id", "user_id"))
    $users = @()
    foreach ($candidate in $candidates) {
        $openId = Get-PropertyValue -Object $candidate -Names @("open_id", "user_id")
        if (-not [string]::IsNullOrWhiteSpace($openId) -and $openId -like "ou_*") {
            $users += $candidate
        }
    }
    if ($users.Count -eq 0) {
        throw "No chatted Feishu user was found for '$Name'."
    }
    $exact = @($users | Where-Object {
        $display = "$(Get-PropertyValue -Object $_ -Names @("name", "localized_name", "en_name", "nickname"))"
        $display -eq $Name
    })
    $selected = if ($exact.Count -gt 0) { $exact[0] } else { $users[0] }
    return "$(Get-PropertyValue -Object $selected -Names @("open_id", "user_id"))"
}

function ConvertTo-PlainMessageText {
    param([object]$Value)
    if ($null -eq $Value) {
        return ""
    }
    if ($Value -is [string]) {
        $text = [System.Net.WebUtility]::HtmlDecode($Value)
        $trimmed = $text.Trim()
        if (($trimmed.StartsWith("{") -and $trimmed.EndsWith("}")) -or ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]"))) {
            try {
                $nested = $trimmed | ConvertFrom-Json
                return ConvertTo-PlainMessageText -Value $nested
            } catch {
                return $text
            }
        }
        return $text
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return (@($Value | ForEach-Object { ConvertTo-PlainMessageText -Value $_ }) -join "`n")
    }
    return (@($Value.PSObject.Properties | ForEach-Object { ConvertTo-PlainMessageText -Value $_.Value }) -join "`n")
}

function Get-WechatUrls {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }
    $matches = [regex]::Matches($Text, 'https?://[^\s"<>)]*mp\.weixin\.qq\.com[^\s"<>)]*')
    $urls = @()
    foreach ($match in $matches) {
        $url = [System.Net.WebUtility]::HtmlDecode($match.Value).TrimEnd(".", ",", ";", [string][char]0xFF0C, [string][char]0x3002, [string][char]0xFF1B, "'")
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            $urls += $url
        }
    }
    return @($urls | Select-Object -Unique)
}

function Get-MessageItems {
    param([object]$Json)
    $objects = @(Find-ObjectsWithProperty -Root $Json -PropertyNames @("message_id", "messageId", "msg_id", "content"))
    return @($objects | Where-Object {
        -not [string]::IsNullOrWhiteSpace((Get-PropertyValue -Object $_ -Names @("message_id", "messageId", "msg_id"))) -or
        -not [string]::IsNullOrWhiteSpace((Get-PropertyValue -Object $_ -Names @("content", "body", "text")))
    })
}

function Get-FeishuMessages {
    param(
        [string]$UserOpenId,
        [string]$StartIso,
        [string]$EndIso
    )
    $pageToken = ""
    $items = @()
    $seenTokens = @{}
    while ($true) {
        $args = @("im", "+chat-messages-list", "--as", "user", "--user-id", $UserOpenId, "--sort", "desc", "--page-size", "$PageSize", "--start", $StartIso, "--end", $EndIso, "--format", "json")
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) {
            $args += @("--page-token", $pageToken)
        }
        $json = Invoke-ReadOnlyCliJson -Executable "lark-cli.cmd" -CliArgs $args
        $items += @(Get-MessageItems -Json $json)

        $hasMore = $false
        if ($null -ne $json.data.has_more) {
            $hasMore = [bool]$json.data.has_more
        } elseif ($null -ne $json.has_more) {
            $hasMore = [bool]$json.has_more
        }
        $nextToken = Get-PropertyValue -Object $json.data -Names @("page_token")
        if ([string]::IsNullOrWhiteSpace($nextToken)) {
            $nextToken = Get-PropertyValue -Object $json -Names @("page_token")
        }
        if (-not $hasMore -or [string]::IsNullOrWhiteSpace($nextToken)) {
            break
        }
        if ($seenTokens.ContainsKey($nextToken)) {
            throw "Feishu message pagination returned a repeated page token."
        }
        $seenTokens[$nextToken] = $true
        $pageToken = $nextToken
    }
    return @($items)
}

function New-QueueFile {
    param(
        [string]$Id,
        [string]$Url,
        [object]$Context
    )
    $path = Join-Path $queueRoot "$Id.md"
    $content = @"
---
type: wechat_link_queue
status: pending
url: "$($Url.Replace('"', '\"'))"
captured_at: "$(Get-Date -Format s)"
source_system: feishu_im
contact_name: "$($ContactName.Replace('"', '\"'))"
message_id: "$($Context.messageId.Replace('"', '\"'))"
message_time: "$($Context.messageTime.Replace('"', '\"'))"
---

# WeChat Link Queue

Use the global `obsidian-wechat-save` skill to save this WeChat public-account article into `10_Sources/Wechat`.

- URL: $Url
- Feishu contact: $ContactName
- Feishu message id: $($Context.messageId)
- Feishu message time: $($Context.messageTime)

## Feishu Message Text

$($Context.messageText)
"@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}

function Set-QueueFileStatus {
    param(
        [string]$Path,
        [string]$Status,
        [string]$NotePath = "",
        [string]$ErrorMessage = ""
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $text = $text -replace "(?m)^status:\s*.*$", "status: $Status"
    if (-not [string]::IsNullOrWhiteSpace($NotePath)) {
        $escapedNotePath = $NotePath.Replace("\", "\\").Replace('"', '\"')
        if ($text -match "(?m)^note_path:") {
            $text = $text -replace "(?m)^note_path:\s*.*$", "note_path: `"$escapedNotePath`""
        } else {
            $text = $text -replace "(?m)^source_system:\s*feishu_im$", "source_system: feishu_im`nnote_path: `"$escapedNotePath`""
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $escapedError = $ErrorMessage.Replace('"', '\"')
        if ($text -match "(?m)^error:") {
            $text = $text -replace "(?m)^error:\s*.*$", "error: `"$escapedError`""
        } else {
            $text = $text -replace "(?m)^---\s*$", "error: `"$escapedError`"`n---"
        }
    }
    Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
}

function New-WechatCapturedNote {
    param(
        [string]$Id,
        [string]$Url,
        [object]$Context
    )

    $existingPath = Find-WechatNoteForUrl -Url $Url
    if (-not [string]::IsNullOrWhiteSpace($existingPath)) {
        return $existingPath
    }

    $date = Get-Date -Format "yyyy-MM-dd"
    $shortId = if ($Id.Length -gt 8) { $Id.Substring(0, 8) } else { $Id }
    $path = New-UniqueMarkdownPath -Directory $wechatRoot -BaseName "$date-WeChat-$shortId"
    $escapedUrl = $Url.Replace('"', '\"')
    $escapedContactName = $ContactName.Replace('"', '\"')
    $escapedMessageId = $Context.messageId.Replace('"', '\"')
    $escapedMessageTime = $Context.messageTime.Replace('"', '\"')
    $content = @"
---
type: source
source_type: wechat
title: "WeChat article pending extraction"
author: ""
url: "$escapedUrl"
captured_at: "$date"
published_at: ""
status: captured
quality: unknown
privacy: public
transcript_path: ""
related_topics: []
source_context: "Feishu chat $escapedContactName, message_id: $escapedMessageId, message_time: $escapedMessageTime"
---

# WeChat article pending extraction

## Source Snapshot

- Why this source matters:
- Original context: Feishu chat $ContactName
- Capture method: read-only Feishu CLI link sync

## Full Text Or Transcript

Original URL: $Url

This source note was created automatically when the Feishu chat scanner found the WeChat URL. Article extraction has not completed yet. If automatic extraction is blocked by a WeChat environment verification page, open the URL manually and enrich this note later.

## Extracted Units

### Viewpoints

- [ ]

### Judgments

- [ ]

### Facts

- [ ]

### Data

- [ ]

## Processing Log

- captured: $date
- extracted_by:
- reviewed_by:

## Notes

"@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}

function Invoke-CodexWechatSave {
    param(
        [string]$Url,
        [object]$Context
    )
    $codexPath = ""
    $codex = Get-Command "codex" -ErrorAction SilentlyContinue
    if ($codex) {
        $codexPath = $codex.Source
    }
    if ([string]::IsNullOrWhiteSpace($codexPath)) {
        $localCodex = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\codex.exe"
        if (Test-Path -LiteralPath $localCodex) {
            $codexPath = $localCodex
        }
    }
    if ([string]::IsNullOrWhiteSpace($codexPath)) {
        throw "codex CLI is not installed or not discoverable; queued link only."
    }
    $prompt = @"
Use the global obsidian-wechat-save skill.

Save this WeChat public-account article into the Obsidian vault:
$Url

Feishu source context:
- contact_name: $ContactName
- message_id: $($Context.messageId)
- message_time: $($Context.messageTime)

Do not edit Feishu. Write only under G:\AI project\obsidian\10_Sources\Wechat unless the skill requires metadata checks.
"@
    Write-RequestLog -Message "codex_wechat_save url=$Url"
    $output = & $codexPath exec --cd $vaultRoot --dangerously-bypass-approvals-and-sandbox $prompt 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Codex wechat save failed: $(($output | Out-String).Trim())"
    }
}

function Find-WechatNoteForUrl {
    param([string]$Url)
    $escaped = [regex]::Escape($Url)
    $hit = Get-ChildItem -LiteralPath $wechatRoot -Filter "*.md" -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $escaped -SimpleMatch -List -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit) {
        return $hit.Path
    }
    return ""
}

$state = Read-State -Path $statePath
$state.contactName = $ContactName
$contactOpenId = Resolve-FeishuContactOpenId -Name $ContactName -State $state
$state.contactOpenId = $contactOpenId

if ([string]::IsNullOrWhiteSpace($Start)) {
    $startIso = (Get-Date).AddDays(-1 * $DaysBack).ToString("s")
} else {
    $startIso = ([datetime]::Parse($Start)).ToString("s")
}
if ([string]::IsNullOrWhiteSpace($End)) {
    $endIso = (Get-Date).ToString("s")
} else {
    $endIso = ([datetime]::Parse($End)).ToString("s")
}

$messages = @(Get-FeishuMessages -UserOpenId $contactOpenId -StartIso $startIso -EndIso $endIso)
$found = 0
$queued = 0
$saved = 0
$skipped = 0
$errors = 0

foreach ($message in $messages) {
    $messageId = Get-PropertyValue -Object $message -Names @("message_id", "messageId", "msg_id", "id")
    $messageTime = Get-PropertyValue -Object $message -Names @("create_time", "created_at", "update_time", "updated_at")
    $messageText = ConvertTo-PlainMessageText -Value $message
    $urls = @(Get-WechatUrls -Text $messageText)
    foreach ($url in $urls) {
        $found++
        $id = Get-StableId -Text $url
        $existing = $state.items.PSObject.Properties[$id]
        if ($null -ne $existing -and $existing.Value.status -eq "saved") {
            $skipped++
            continue
        }
        $context = [pscustomobject]@{
            messageId = "$messageId"
            messageTime = "$messageTime"
            messageText = "$messageText"
        }
        if ($DryRun) {
            Write-Host "[dry-run] Would queue WeChat URL from Feishu contact '$ContactName': $url"
            $queued++
            continue
        }

        try {
            $queuePath = New-QueueFile -Id $id -Url $url -Context $context
            $notePath = New-WechatCapturedNote -Id $id -Url $url -Context $context
            Set-QueueFileStatus -Path $queuePath -Status "captured" -NotePath $notePath
            $status = "captured"
            $saveError = ""
            if ($SaveWithCodex) {
                try {
                    Invoke-CodexWechatSave -Url $url -Context $context
                    $notePath = Find-WechatNoteForUrl -Url $url
                    $status = if ([string]::IsNullOrWhiteSpace($notePath)) { "queued_after_codex" } else { "saved" }
                } catch {
                    $saveError = $_.Exception.Message
                    $status = "captured"
                    Set-QueueFileStatus -Path $queuePath -Status "captured" -NotePath $notePath -ErrorMessage $saveError
                    Write-RequestLog -Message "codex_save_error url=$url message=$saveError"
                }
                if ($status -eq "saved") {
                    $saved++
                } else {
                    $queued++
                }
            } else {
                $queued++
            }
            Add-OrUpdateItem -ItemsObject $state.items -Key $id -Value ([pscustomobject]@{
                url = $url
                status = $status
                firstSeenAt = (Get-Date).ToString("s")
                lastSeenAt = (Get-Date).ToString("s")
                contactName = $ContactName
                contactOpenId = $contactOpenId
                messageId = "$messageId"
                messageTime = "$messageTime"
                queuePath = $queuePath
                notePath = $notePath
                error = $saveError
            })
            Save-State -State $state -Path $statePath
        } catch {
            $errors++
            Write-RequestLog -Message "item_error url=$url message=$($_.Exception.Message)"
            Add-OrUpdateItem -ItemsObject $state.items -Key $id -Value ([pscustomobject]@{
                url = $url
                status = "error"
                firstSeenAt = (Get-Date).ToString("s")
                lastSeenAt = (Get-Date).ToString("s")
                contactName = $ContactName
                contactOpenId = $contactOpenId
                messageId = "$messageId"
                messageTime = "$messageTime"
                queuePath = ""
                notePath = ""
                error = $_.Exception.Message
            })
            Save-State -State $state -Path $statePath
        }
    }
}

if (-not $DryRun) {
    Save-State -State $state -Path $statePath
}

$logPath = Join-Path $logRoot "feishu-wechat-sync-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').log"
$summaryLine = "found=$found queued=$queued saved=$saved skipped=$skipped errors=$errors dryRun=$DryRun saveWithCodex=$SaveWithCodex contactName=$ContactName start=$startIso end=$endIso"
@($summaryLine) + $script:RequestLogEntries | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "Feishu WeChat sync finished. found=$found queued=$queued saved=$saved skipped=$skipped errors=$errors dryRun=$DryRun saveWithCodex=$SaveWithCodex"
Write-Host "Log: $logPath"
