param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$sourceRoot = Join-Path $vaultRoot "10_Sources"

function Set-FrontmatterField {
    param(
        [string]$Frontmatter,
        [string]$Name,
        [string]$Value
    )

    $escapedValue = $Value.Replace('"', '\"')
    $line = if ($Value -match "^(interview|meeting|personal_recording|unknown|low|medium|high)$") {
        "$Name`: $Value"
    } else {
        "$Name`: `"$escapedValue`""
    }

    if ($Frontmatter -match "(?m)^$([regex]::Escape($Name)):\s*.*$") {
        return [regex]::Replace($Frontmatter, "(?m)^$([regex]::Escape($Name)):\s*.*$", $line)
    }
    return ($Frontmatter.TrimEnd() + "`n" + $line)
}

function Update-FeishuClassification {
    param(
        [string]$Path,
        [switch]$DryRun
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -notmatch "(?s)^---\s*\r?\n(.*?)\r?\n---\s*(.*)$") {
        return [pscustomobject]@{ changed = $false; message = "skip_no_frontmatter"; path = $Path }
    }

    $frontmatter = $Matches[1]
    $body = $Matches[2]
    $map = Get-FrontmatterMap -Path $Path
    if ($null -eq $map -or $map["source_type"] -ne "feishu_minutes") {
        return [pscustomobject]@{ changed = $false; message = "skip_not_feishu"; path = $Path }
    }

    $title = if ($map.ContainsKey("title")) { $map["title"] } else { [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $classification = Get-FeishuContentKind -Title $title -Content $body

    $newFrontmatter = $frontmatter
    $newFrontmatter = Set-FrontmatterField -Frontmatter $newFrontmatter -Name "content_kind" -Value $classification.kind
    $newFrontmatter = Set-FrontmatterField -Frontmatter $newFrontmatter -Name "content_kind_confidence" -Value $classification.confidence
    $newFrontmatter = Set-FrontmatterField -Frontmatter $newFrontmatter -Name "content_kind_reason" -Value $classification.reason

    $changed = $newFrontmatter -ne $frontmatter
    if ($changed -and -not $DryRun) {
        $newContent = "---`n$newFrontmatter`n---`n$body"
        Set-Content -LiteralPath $Path -Value $newContent -Encoding UTF8
    }

    return [pscustomobject]@{
        changed = $changed
        message = "content_kind=$($classification.kind) confidence=$($classification.confidence) reason=$($classification.reason)"
        path = $Path
    }
}

$notes = Get-ChildItem -LiteralPath $sourceRoot -File -Filter "*.md" | Where-Object {
    $_.FullName -notmatch "\\Attachments\\"
}

$changedCount = 0
$scannedCount = 0
foreach ($note in $notes) {
    $result = Update-FeishuClassification -Path $note.FullName -DryRun:$DryRun
    if ($result.message -notlike "skip_*") {
        $scannedCount++
        if ($result.changed) {
            $changedCount++
            $prefix = if ($DryRun) { "[dry-run]" } else { "[updated]" }
            Write-Host "$prefix $($result.path) $($result.message)"
        } else {
            Write-Host "[unchanged] $($result.path) $($result.message)"
        }
    }
}

Write-Host "Feishu classification finished. scanned=$scannedCount changed=$changedCount dryRun=$DryRun"
