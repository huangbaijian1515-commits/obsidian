param(
    [string]$VaultRoot = (Resolve-Path ".").Path
)

$ErrorActionPreference = "Stop"

function Get-MarkdownFiles {
    param([string]$Root)
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.md" |
        Where-Object { $_.FullName -notmatch "\\\.git\\" }
}

function Get-Frontmatter {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -notmatch "(?s)^---\s*\r?\n(.*?)\r?\n---") {
        return $null
    }

    $map = @{}
    $lines = $Matches[1] -split "\r?\n"
    foreach ($line in $lines) {
        if ($line -match "^\s*([A-Za-z0-9_-]+):\s*(.*)\s*$") {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $map
}

function Get-RelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\") + "\"
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $rootUri = New-Object System.Uri($rootFull)
    $pathUri = New-Object System.Uri($pathFull)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace("\", "/")
}

$sourceRequired = @(
    "type",
    "source_type",
    "title",
    "captured_at",
    "status",
    "quality",
    "privacy",
    "related_topics"
)

$queryRequired = @(
    "type",
    "status",
    "confidence",
    "domains",
    "topics",
    "source_notes",
    "supports",
    "contradicts",
    "aliases",
    "last_reviewed"
)

$files = Get-MarkdownFiles -Root $VaultRoot
$missingFrontmatter = @()
$missingFields = @()
$unprocessedSources = @()
$queryWithoutEvidence = @()
$privacyWarnings = @()

foreach ($file in $files) {
    $relative = Get-RelativePath -Root $VaultRoot -Path $file.FullName
    if ([System.IO.Path]::GetFileName($file.FullName) -eq "README.md") {
        continue
    }
    if ($relative.StartsWith("90_System/Templates/")) {
        continue
    }

    $frontmatter = Get-Frontmatter -Path $file.FullName
    $isKnowledgeNote = $relative.StartsWith("10_Sources/") -or $relative.StartsWith("20_Query/") -or $relative.StartsWith("30_Topics/") -or $relative.StartsWith("40_Wiki/")

    if ($isKnowledgeNote -and $null -eq $frontmatter) {
        $missingFrontmatter += $relative
        continue
    }

    if ($null -eq $frontmatter) {
        continue
    }

    $type = $frontmatter["type"]

    if ($relative.StartsWith("10_Sources/") -or $type -eq "source") {
        foreach ($field in $sourceRequired) {
            if (-not $frontmatter.ContainsKey($field)) {
                $missingFields += "$relative -> missing field: $field"
            }
        }

        $status = $frontmatter["status"]
        if ($status -eq "captured" -or $status -eq "transcribed") {
            $unprocessedSources += "$relative -> status: $status"
        }

        $privacy = $frontmatter["privacy"]
        if ($privacy -eq "work" -or $privacy -eq "sensitive") {
            $privacyWarnings += "$relative -> privacy: $privacy"
        }
    }

    if ($relative.StartsWith("20_Query/") -or @("claim", "concept", "case", "data") -contains $type) {
        foreach ($field in $queryRequired) {
            if (-not $frontmatter.ContainsKey($field)) {
                $missingFields += "$relative -> missing field: $field"
            }
        }

        $sourceNotes = $frontmatter["source_notes"]
        if ([string]::IsNullOrWhiteSpace($sourceNotes) -or $sourceNotes -eq "[]") {
            $queryWithoutEvidence += "$relative -> empty source_notes"
        }

        if ($frontmatter["confidence"] -eq "low" -and $frontmatter["status"] -eq "reviewed") {
            $privacyWarnings += "$relative -> reviewed but confidence is low"
        }
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$reportPath = Join-Path $VaultRoot "50_Lint/vault-lint-$timestamp.md"

$lines = @()
$lines += "---"
$lines += "type: lint_report"
$lines += "generated_at: `"$timestamp`""
$lines += "status: open"
$lines += "---"
$lines += ""
$lines += "# Vault Lint Report $timestamp"
$lines += ""
$lines += "## Summary"
$lines += ""
$lines += "- Markdown files scanned: $($files.Count)"
$lines += "- Missing frontmatter: $($missingFrontmatter.Count)"
$lines += "- Missing fields: $($missingFields.Count)"
$lines += "- Unprocessed sources: $($unprocessedSources.Count)"
$lines += "- Query notes without evidence: $($queryWithoutEvidence.Count)"
$lines += "- Privacy or confidence warnings: $($privacyWarnings.Count)"
$lines += ""

function Add-Section {
    param(
        [string]$Title,
        [array]$Items
    )
    $script:lines += "## $Title"
    $script:lines += ""
    if ($Items.Count -eq 0) {
        $script:lines += "No issues found."
    } else {
        foreach ($item in $Items) {
            $script:lines += "- $item"
        }
    }
    $script:lines += ""
}

Add-Section -Title "Missing Frontmatter" -Items $missingFrontmatter
Add-Section -Title "Missing Fields" -Items $missingFields
Add-Section -Title "Unprocessed Sources" -Items $unprocessedSources
Add-Section -Title "Query Notes Without Evidence" -Items $queryWithoutEvidence
Add-Section -Title "Privacy Or Confidence Warnings" -Items $privacyWarnings

$lines += "## Recommended Repairs"
$lines += ""
$lines += "- Convert valuable inbox items into source notes."
$lines += "- Fill missing frontmatter before promotion."
$lines += "- Keep work or sensitive material out of cloud AI tools."
$lines += "- Promote only reviewed source extractions into query notes."

Set-Content -LiteralPath $reportPath -Value $lines -Encoding UTF8
Write-Host "Lint report written to $reportPath"
