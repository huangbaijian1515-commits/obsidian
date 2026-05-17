param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot

function Test-PythonModule {
    param([string]$Module)

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        return $false
    }

    try {
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        & python -c "import $Module" *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Get-CommandInfo {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return @{
            installed = $false
            path = ""
        }
    }
    return @{
        installed = $true
        path = $cmd.Source
    }
}

$lark = Get-CommandInfo -Name "lark-cli"
$ffmpeg = Get-CommandInfo -Name "ffmpeg"
$python = Get-CommandInfo -Name "python"
$fasterWhisper = Test-PythonModule -Module "faster_whisper"

$larkHelp = ""
$larkAuthProbe = ""
if ($lark.installed) {
    $larkHelp = (& lark-cli --help 2>&1 | Select-Object -First 30) -join "`n"
    $larkAuthProbe = (& lark-cli auth 2>&1 | Select-Object -First 30) -join "`n"
}

$result = [ordered]@{
    vaultRoot = $vaultRoot
    checkedAt = (Get-Date).ToString("s")
    dependencies = [ordered]@{
        larkCli = $lark
        ffmpeg = $ffmpeg
        python = $python
        fasterWhisperPythonModule = @{
            installed = $fasterWhisper
            module = "faster_whisper"
        }
    }
    larkCliHints = [ordered]@{
        loginCommand = "lark-cli auth login --recommend"
        helpPreview = $larkHelp
        authPreview = $larkAuthProbe
    }
    safety = [ordered]@{
        readOnly = $true
        forbiddenOperations = @("edit", "update", "delete", "remove", "upload", "move", "comment", "write")
        requiredReadScopes = @("minutes:minutes.search:read", "minutes:minutes:readonly", "minutes:minutes.basic:read")
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-Host "Vault: $vaultRoot"
    Write-Host "lark-cli installed: $($lark.installed) $($lark.path)"
    Write-Host "ffmpeg installed: $($ffmpeg.installed) $($ffmpeg.path)"
    Write-Host "python installed: $($python.installed) $($python.path)"
    Write-Host "faster_whisper module installed: $fasterWhisper"
    if (-not $lark.installed) {
        Write-Host "Install Feishu CLI, then run: lark-cli auth login --recommend"
    } else {
        Write-Host "Required read scopes include: minutes:minutes.search:read, minutes:minutes:readonly, minutes:minutes.basic:read"
        Write-Host "If sync reports need_user_authorization, re-run lark-cli auth login --recommend and approve the minutes read scopes."
    }
    if ($lark.installed) {
        Write-Host ""
        Write-Host "lark-cli help preview:"
        Write-Host $larkHelp
    }
}
