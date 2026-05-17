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
        [string]$TranscriptUnavailableReason = ""
    )

    $date = ConvertTo-NoteDate -Value $SourceDate
    $safeTitle = ConvertTo-SafeFileName -Text $Title
    $sourceDir = Join-Path $VaultRoot "10_Sources"
    $path = New-UniqueMarkdownPath -Directory $sourceDir -BaseName "$date`_$safeTitle"

    $escapedTitle = $Title.Replace('"', '\"')
    $escapedUrl = $FeishuUrl.Replace('"', '\"')
    $escapedTranscriptPath = $TranscriptPath.Replace('"', '\"')
    $escapedFeishuId = $FeishuId.Replace('"', '\"')
    $escapedUpdatedAt = $UpdatedAt.Replace('"', '\"')
    $escapedTranscriptUnavailableReason = $TranscriptUnavailableReason.Replace('"', '\"')
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
