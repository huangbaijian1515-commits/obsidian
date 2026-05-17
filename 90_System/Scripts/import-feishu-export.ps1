param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [string]$Title = "",

    [ValidateSet("personal", "work", "sensitive")]
    [string]$Privacy = "work"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$content = Get-Content -LiteralPath $InputFile -Raw

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
}

$path = New-SourceNote -VaultRoot $vaultRoot -Title $Title -SourceType "feishu_minutes" -Privacy $Privacy -Quality "medium" -Status "transcribed" -Body $content
Write-Host "Feishu source note created: $path"

