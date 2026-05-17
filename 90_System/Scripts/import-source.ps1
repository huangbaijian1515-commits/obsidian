param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [ValidateSet("web", "wechat", "youtube", "feishu_minutes", "sheet", "manual")]
    [string]$SourceType = "web",

    [string]$Url = "",
    [string]$Author = "",
    [string]$PublishedAt = "",

    [ValidateSet("public", "personal", "work", "sensitive")]
    [string]$Privacy = "public",

    [ValidateSet("high", "medium", "low", "unknown")]
    [string]$Quality = "unknown",

    [string]$InputFile = "",
    [switch]$FetchUrl
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$body = ""

if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
    $body = Get-Content -LiteralPath $InputFile -Raw
} elseif ($FetchUrl -and -not [string]::IsNullOrWhiteSpace($Url)) {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    $body = $response.Content
} else {
    $body = "Paste full text, transcript, export, or a local file reference here."
}

$path = New-SourceNote -VaultRoot $vaultRoot -Title $Title -SourceType $SourceType -Url $Url -Author $Author -PublishedAt $PublishedAt -Privacy $Privacy -Quality $Quality -Body $body
Write-Host "Source note created: $path"

