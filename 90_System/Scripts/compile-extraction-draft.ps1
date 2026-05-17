param(
    [ValidateSet("captured", "transcribed", "all")]
    [string]$Status = "all"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$sourceDir = Join-Path $vaultRoot "10_Sources"
$draftDir = Join-Path $vaultRoot "00_Inbox\Extraction_Drafts"
New-Item -ItemType Directory -Force -Path $draftDir | Out-Null

$sources = Get-ChildItem -LiteralPath $sourceDir -File -Filter "*.md" |
    Where-Object { $_.Name -ne "README.md" } |
    ForEach-Object {
        $fm = Get-FrontmatterMap -Path $_.FullName
        [PSCustomObject]@{
            Path = $_.FullName
            Name = $_.Name
            Frontmatter = $fm
        }
    } |
    Where-Object {
        $null -ne $_.Frontmatter -and (
            $Status -eq "all" -or $_.Frontmatter["status"] -eq $Status
        )
    }

$timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$draftPath = Join-Path $draftDir "extraction-draft-$timestamp.md"
$lines = @()
$lines += "---"
$lines += "type: extraction_draft"
$lines += "generated_at: `"$timestamp`""
$lines += "status: pending_review"
$lines += "---"
$lines += ""
$lines += "# Extraction Draft $timestamp"
$lines += ""
$lines += 'Use this draft with Codex. Review every candidate before promoting anything into `20_Query/`.'
$lines += ""

foreach ($source in $sources) {
    $relative = Resolve-Path -LiteralPath $source.Path -Relative
    $title = $source.Frontmatter["title"]
    $sourceType = $source.Frontmatter["source_type"]
    $privacy = $source.Frontmatter["privacy"]
    $sourceStatus = $source.Frontmatter["status"]
    $body = Get-MarkdownBody -Path $source.Path
    $preview = ($body -replace "\s+", " ").Trim()
    if ($preview.Length -gt 1200) {
        $preview = $preview.Substring(0, 1200) + "..."
    }

    $lines += "## $title"
    $lines += ""
    $lines += ('- Source: `{0}`' -f $relative)
    $lines += ('- Type: {0}' -f $sourceType)
    $lines += ('- Status: {0}' -f $sourceStatus)
    $lines += ('- Privacy: {0}' -f $privacy)
    $lines += ""
    $lines += "### Source Preview"
    $lines += ""
    $lines += $preview
    $lines += ""
    $lines += "### Candidate Viewpoints"
    $lines += ""
    $lines += "- [ ] "
    $lines += ""
    $lines += "### Candidate Judgments"
    $lines += ""
    $lines += "- [ ] "
    $lines += ""
    $lines += "### Candidate Facts"
    $lines += ""
    $lines += "- [ ] "
    $lines += ""
    $lines += "### Candidate Data"
    $lines += ""
    $lines += "- [ ] "
    $lines += ""
    $lines += "### Suggested Query Notes"
    $lines += ""
    $lines += "- [ ] "
    $lines += ""
}

Set-Content -LiteralPath $draftPath -Value $lines -Encoding UTF8
Write-Host "Extraction draft written to $draftPath"
