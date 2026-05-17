param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$Title = "",

    [ValidateSet("public", "personal", "work", "sensitive")]
    [string]$Privacy = "public"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$ytDlp = Get-Command yt-dlp -ErrorAction SilentlyContinue
$body = ""
$status = "captured"
$author = ""
$publishedAt = ""

if ($ytDlp) {
    $json = & yt-dlp --dump-json --skip-download $Url | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = $json.title
    }
    $author = $json.channel
    $publishedAt = $json.upload_date
    $body = @"
Metadata captured with yt-dlp.

- Channel: $author
- Upload date: $publishedAt
- Duration: $($json.duration) seconds

Transcript is not downloaded by this script yet. Add subtitles or transcript below, then change status to `transcribed`.
"@
} else {
    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = "YouTube Source $(Get-Date -Format 'yyyy-MM-dd HHmm')"
    }
    $body = @"
yt-dlp is not installed, so only the URL was captured.

Next steps:

1. Add title, channel, and published date.
2. Paste transcript or subtitle export here.
3. Change status to `transcribed`.
"@
}

$path = New-SourceNote -VaultRoot $vaultRoot -Title $Title -SourceType "youtube" -Url $Url -Author $author -PublishedAt $publishedAt -Privacy $Privacy -Quality "unknown" -Status $status -Body $body
Write-Host "YouTube source note created: $path"

