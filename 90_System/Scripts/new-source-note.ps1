param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [ValidateSet("web", "wechat", "youtube", "feishu_minutes", "sheet", "manual")]
    [string]$SourceType = "web",

    [string]$Url = "",

    [ValidateSet("public", "personal", "work", "sensitive")]
    [string]$Privacy = "public"
)

$ErrorActionPreference = "Stop"

function Convert-ToSlug {
    param([string]$Text)
    $slug = $Text.ToLowerInvariant()
    $slug = $slug -replace "[^\p{L}\p{Nd}]+", "-"
    $slug = $slug.Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "untitled"
    }
    return $slug
}

$vaultRoot = (Resolve-Path ".").Path
$date = Get-Date -Format "yyyy-MM-dd"
$slug = Convert-ToSlug -Text $Title
$fileName = "$date-$slug.md"
$path = Join-Path $vaultRoot "10_Sources/$fileName"

if (Test-Path -LiteralPath $path) {
    throw "Source note already exists: $path"
}

$content = @"
---
type: source
source_type: $SourceType
title: "$Title"
author: ""
url: "$Url"
captured_at: "$date"
published_at: ""
status: captured
quality: unknown
privacy: $Privacy
transcript_path: ""
related_topics: []
---

# $Title

## Source Snapshot

- Why this source matters:
- Original context:
- Capture method:

## Full Text Or Transcript

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
Write-Host "Source note created: $path"

