function Get-VaultRoot {
    param([string]$StartPath = (Get-Location).Path)

    $current = Resolve-Path -LiteralPath $StartPath
    while ($null -ne $current) {
        if (Test-Path -LiteralPath (Join-Path $current "90_System")) {
            return $current.Path
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current.Path) {
            break
        }
        $current = Resolve-Path -LiteralPath $parent
    }

    throw "Could not find vault root. Run this script from inside the Obsidian vault."
}

function ConvertTo-Slug {
    param([string]$Text)

    $slug = $Text.ToLowerInvariant()
    $slug = $slug -replace "[^\p{L}\p{Nd}]+", "-"
    $slug = $slug.Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "untitled"
    }
    return $slug
}

function ConvertTo-SafeFileName {
    param([string]$Text)

    $safe = $Text -replace '[\\/:*?"<>|]', "-"
    $safe = $safe -replace "\s+", " "
    $safe = $safe.Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "untitled"
    }
    return $safe
}

function ConvertTo-NoteDate {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return (Get-Date -Format "yyyy-MM-dd")
    }

    [DateTime]$parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse($Value, [ref]$parsed)) {
        return $parsed.ToString("yyyy-MM-dd")
    }

    if ($Value -match "^\d{8}$") {
        return "{0}-{1}-{2}" -f $Value.Substring(0, 4), $Value.Substring(4, 2), $Value.Substring(6, 2)
    }

    if ($Value -match "^\d{10,13}$") {
        $epoch = [DateTimeOffset]::FromUnixTimeSeconds([int64]($Value.Substring(0, 10))).LocalDateTime
        return $epoch.ToString("yyyy-MM-dd")
    }

    return (Get-Date -Format "yyyy-MM-dd")
}

function Measure-KeywordHits {
    param(
        [string]$Text,
        [string[]]$Keywords
    )

    $hits = @()
    foreach ($keyword in $Keywords) {
        if (-not [string]::IsNullOrWhiteSpace($keyword) -and $Text -match [regex]::Escape($keyword)) {
            $hits += $keyword
        }
    }
    return @($hits)
}

function ConvertFrom-Base64Utf8 {
    param([string]$Value)

    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Value))
}

function Get-FeishuContentKind {
    param(
        [string]$Title = "",
        [string]$Content = ""
    )

    $titleText = if ($null -eq $Title) { "" } else { "$Title" }
    $contentText = if ($null -eq $Content) { "" } else { "$Content" }
    $combined = "$contentText`n$titleText"
    $hasContent = -not [string]::IsNullOrWhiteSpace($contentText)

    $interviewKeywords = @("6Ieq5oiR5LuL57uN", "6Z2i6K+V5a6Y", "5bqU6IGY", "5YCZ6YCJ5Lq6", "566A5Y6G", "5bel5L2c57uP5Y6G", "5Li65LuA5LmI5p2l6Z2i6K+V", "5bKX5L2N", "6Z2i6K+V", "6IGM5Lia57uP5Y6G", "56a76IGM5Y6f5Zug") | ForEach-Object { ConvertFrom-Base64Utf8 $_ }
    $meetingKeywords = @("5pa55qGI", "6K+E5Lyw", "5aSN55uY", "6KeE5YiS", "5pWw5o2u5YiG5p6Q", "5pS255uK54K5", "6aKE566X", "6aOO6Zmp", "5a6i5oi35qGI5L6L", "6aG555uu5o6o6L+b", "6K6o6K66", "6K+E5a6h", "5rKf6YCa", "5oyH5qCH", "562W55Wl", "5o6S5pyf") | ForEach-Object { ConvertFrom-Base64Utf8 $_ }
    $recordingKeywords = @("RPReplay", "5paw5b2V6Z+z", "5b2V5bGP", "5bGP5bmV5b2V5Yi2") | ForEach-Object {
        if ($_ -eq "RPReplay") { $_ } else { ConvertFrom-Base64Utf8 $_ }
    }

    $interviewHits = @(Measure-KeywordHits -Text $combined -Keywords $interviewKeywords)
    $meetingHits = @(Measure-KeywordHits -Text $combined -Keywords $meetingKeywords)
    $recordingHits = @(Measure-KeywordHits -Text $combined -Keywords $recordingKeywords)

    $speakerTurns = ([regex]::Matches($contentText, "$(ConvertFrom-Base64Utf8 '6K+06K+d5Lq6')\s*\d+")).Count
    $strongInterviewSignals = 0
    if ($contentText -match (ConvertFrom-Base64Utf8 "6Ieq5oiR5LuL57uN")) {
        $interviewHits += (ConvertFrom-Base64Utf8 "6Ieq5oiR5LuL57uN")
        $interviewHits += "interview_intro_signal"
        $strongInterviewSignals += 2
    }
    $hasInterviewMotivationSignal = ($contentText -match (ConvertFrom-Base64Utf8 "55yL5py65Lya") -or $contentText -match (ConvertFrom-Base64Utf8 "56a76IGM"))
    $hasInterviewContextSignal = ($combined -match (ConvertFrom-Base64Utf8 "6Z2i6K+V") -or $combined -match (ConvertFrom-Base64Utf8 "5YCZ6YCJ5Lq6") -or $combined -match (ConvertFrom-Base64Utf8 "566A5Y6G") -or $combined -match (ConvertFrom-Base64Utf8 "6Z2i6K+V5a6Y") -or $combined -match (ConvertFrom-Base64Utf8 "5bqU6IGY") -or $combined -match (ConvertFrom-Base64Utf8 "6Ieq5oiR5LuL57uN"))
    if ($hasInterviewMotivationSignal -and $hasInterviewContextSignal) {
        $interviewHits += "interview_motivation_pattern"
        $strongInterviewSignals += 2
    }
    if ($contentText -match (ConvertFrom-Base64Utf8 "5YWI6Ieq5oiR5LuL57uN") -or $contentText -match (ConvertFrom-Base64Utf8 "5LuL57uN5LiA5LiLLirnu4/ljoY=") -or $contentText -match (ConvertFrom-Base64Utf8 "5Li65LuA5LmILirpnaLor5U=")) {
        $interviewHits += "interview_dialogue_pattern"
        $strongInterviewSignals += 1
    }
    if ($contentText -match (ConvertFrom-Base64Utf8 "5p2l6Z2i6K+VLirljp/lm6A=") -or $contentText -match (ConvertFrom-Base64Utf8 "6Z2i6K+VLirlspfkvY0=") -or $contentText -match (ConvertFrom-Base64Utf8 "5bqU6IGYLirlspfkvY0=")) {
        $interviewHits += "interview_intent_pattern"
        $strongInterviewSignals += 1
    }
    if ($contentText -match (ConvertFrom-Base64Utf8 "5ZyoLirlt6XkvZwuKuW5tA==") -or $contentText -match (ConvertFrom-Base64Utf8 "5LmL5YmNLirlt6XkvZw=") -or $contentText -match (ConvertFrom-Base64Utf8 "55uu5YmNLirmi4Xku7s=")) {
        $interviewHits += "career_background_pattern"
        $strongInterviewSignals += 1
    }
    if ($strongInterviewSignals -eq 0 -and $speakerTurns -ge 8 -and ($contentText -match (ConvertFrom-Base64Utf8 "5pa55qGI") -or $contentText -match (ConvertFrom-Base64Utf8 "5pWw5o2u") -or $contentText -match (ConvertFrom-Base64Utf8 "6aKE566X") -or $contentText -match (ConvertFrom-Base64Utf8 "6aOO6Zmp"))) {
        $meetingHits += "business_discussion_pattern"
    }

    $kind = "unknown"
    $confidence = "low"
    $reason = "insufficient_signals"

    if ($strongInterviewSignals -ge 2 -or ($interviewHits.Count -ge 2 -and $interviewHits.Count -ge ($meetingHits.Count + 1))) {
        $kind = "interview"
        $confidence = if ($hasContent -and ($interviewHits.Count -ge 4 -or $strongInterviewSignals -ge 2)) { "high" } elseif ($hasContent) { "medium" } else { "low" }
        $reason = "interview_signals: " + (($interviewHits | Select-Object -Unique | Select-Object -First 6) -join ", ")
    } elseif ($meetingHits.Count -ge 3 -and $meetingHits.Count -ge $interviewHits.Count) {
        $kind = "meeting"
        $confidence = if ($hasContent -and $meetingHits.Count -ge 5) { "high" } elseif ($hasContent) { "medium" } else { "low" }
        $reason = "meeting_signals: " + (($meetingHits | Select-Object -Unique | Select-Object -First 6) -join ", ")
    } elseif ($recordingHits.Count -gt 0 -and $interviewHits.Count -eq 0 -and $meetingHits.Count -lt 2) {
        $kind = "personal_recording"
        $confidence = if ($hasContent) { "medium" } else { "low" }
        $reason = "recording_signals: " + (($recordingHits | Select-Object -Unique | Select-Object -First 4) -join ", ")
    } elseif (-not $hasContent) {
        if ($titleText -match (ConvertFrom-Base64Utf8 "6Z2i6K+V")) {
            $kind = "interview"
            $reason = "title_only_signal: interview_keyword"
        } elseif ($titleText -match "$(ConvertFrom-Base64Utf8 '5Lya6K6u')|$(ConvertFrom-Base64Utf8 '5aSN55uY')|$(ConvertFrom-Base64Utf8 '6KeE5YiS')|$(ConvertFrom-Base64Utf8 '6K6o6K66')|$(ConvertFrom-Base64Utf8 '6K+E5a6h')|$(ConvertFrom-Base64Utf8 '5rKf6YCa')|$(ConvertFrom-Base64Utf8 '562U6L6p')") {
            $kind = "meeting"
            $reason = "title_only_signal: meeting_keyword"
        }
        $confidence = "low"
    }

    return [pscustomobject]@{
        kind = $kind
        confidence = $confidence
        reason = $reason
    }
}

function New-UniqueMarkdownPath {
    param(
        [string]$Directory,
        [string]$BaseName
    )

    $candidate = Join-Path $Directory "$BaseName.md"
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $index = 2
    while ($true) {
        $candidate = Join-Path $Directory "$BaseName-$index.md"
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
        $index++
    }
}

function New-UniquePath {
    param(
        [string]$Directory,
        [string]$BaseName,
        [string]$Extension
    )

    $candidate = Join-Path $Directory "$BaseName$Extension"
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $index = 2
    while ($true) {
        $candidate = Join-Path $Directory "$BaseName-$index$Extension"
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
        $index++
    }
}

function New-SourceNote {
    param(
        [string]$VaultRoot,
        [string]$Title,
        [string]$SourceType,
        [string]$Url = "",
        [string]$Author = "",
        [string]$PublishedAt = "",
        [string]$Privacy = "public",
        [string]$Quality = "unknown",
        [string]$Status = "captured",
        [string]$Body = "",
        [string]$TranscriptPath = ""
    )

    $date = Get-Date -Format "yyyy-MM-dd"
    $slug = ConvertTo-Slug -Text $Title
    $sourceDir = Join-Path $VaultRoot "10_Sources"
    $path = New-UniqueMarkdownPath -Directory $sourceDir -BaseName "$date-$slug"

    $escapedTitle = $Title.Replace('"', '\"')
    $escapedAuthor = $Author.Replace('"', '\"')
    $escapedUrl = $Url.Replace('"', '\"')
    $escapedPublishedAt = $PublishedAt.Replace('"', '\"')
    $escapedTranscriptPath = $TranscriptPath.Replace('"', '\"')

    $content = @"
---
type: source
source_type: $SourceType
title: "$escapedTitle"
author: "$escapedAuthor"
url: "$escapedUrl"
captured_at: "$date"
published_at: "$escapedPublishedAt"
status: $Status
quality: $Quality
privacy: $Privacy
transcript_path: "$escapedTranscriptPath"
related_topics: []
---

# $Title

## Source Snapshot

- Why this source matters:
- Original context:
- Capture method:

## Full Text Or Transcript

$Body

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
- transcribed:
- extracted_by:
- reviewed_by:

## Notes

"@

    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}

function New-FeishuSourceNote {
    param(
        [string]$VaultRoot,
        [string]$Title,
        [string]$SourceDate,
        [string]$FeishuId = "",
        [string]$FeishuUrl = "",
        [string]$UpdatedAt = "",
        [string]$Body = "",
        [string]$TranscriptPath = "",
        [bool]$NeedsTranscription = $false,
        [string]$Status = "transcribed",
        [string]$TranscriptUnavailableReason = "",
        [string]$ContentKind = "unknown",
        [string]$ContentKindConfidence = "low",
        [string]$ContentKindReason = ""
    )

    $date = ConvertTo-NoteDate -Value $SourceDate
    $safeTitle = ConvertTo-SafeFileName -Text $Title
    $sourceDir = Join-Path $VaultRoot "10_Sources\Feishu-minutes"
    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
    $path = New-UniqueMarkdownPath -Directory $sourceDir -BaseName "$date`_$safeTitle"

    $escapedTitle = $Title.Replace('"', '\"')
    $escapedUrl = $FeishuUrl.Replace('"', '\"')
    $escapedTranscriptPath = $TranscriptPath.Replace('"', '\"')
    $escapedFeishuId = $FeishuId.Replace('"', '\"')
    $escapedUpdatedAt = $UpdatedAt.Replace('"', '\"')
    $escapedTranscriptUnavailableReason = $TranscriptUnavailableReason.Replace('"', '\"')
    $escapedContentKindReason = $ContentKindReason.Replace('"', '\"')
    $needs = $NeedsTranscription.ToString().ToLowerInvariant()
    $captured = Get-Date -Format "yyyy-MM-dd"

    $content = @"
---
type: source
source_type: feishu_minutes
title: "$escapedTitle"
author: ""
url: "$escapedUrl"
captured_at: "$captured"
published_at: "$date"
status: $Status
quality: medium
privacy: work
transcript_path: "$escapedTranscriptPath"
related_topics: []
feishu_id: "$escapedFeishuId"
feishu_updated_at: "$escapedUpdatedAt"
needs_transcription: $needs
transcript_unavailable_reason: "$escapedTranscriptUnavailableReason"
content_kind: $ContentKind
content_kind_confidence: $ContentKindConfidence
content_kind_reason: "$escapedContentKindReason"
---

# $Title

## Source Snapshot

- Source system: Feishu Minutes
- Feishu id: $FeishuId
- Feishu updated at: $UpdatedAt
- Capture method: read-only Feishu CLI sync

## Full Text Or Transcript

$Body

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

- captured: $captured
- transcribed:
- extracted_by:
- reviewed_by:

## Notes

"@

    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    return $path
}

function Get-FrontmatterMap {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -notmatch "(?s)^---\s*\r?\n(.*?)\r?\n---") {
        return $null
    }

    $map = @{}
    foreach ($line in ($Matches[1] -split "\r?\n")) {
        if ($line -match "^\s*([A-Za-z0-9_-]+):\s*(.*)\s*$") {
            $map[$Matches[1]] = $Matches[2].Trim().Trim('"')
        }
    }
    return $map
}

function Get-MarkdownBody {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    return ($content -replace "(?s)^---\s*\r?\n.*?\r?\n---\s*", "")
}
