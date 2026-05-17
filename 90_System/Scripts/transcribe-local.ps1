param(
    [Parameter(Mandatory = $true)]
    [string]$MediaFile,

    [string]$OutputFile = "",

    [string]$Model = "small",

    [string]$Language = "zh"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_vault-lib.ps1"

$vaultRoot = Get-VaultRoot
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    throw "Python is not installed or not on PATH. Install Python, then install faster-whisper."
}

& python -c "import faster_whisper" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Python module faster_whisper is not installed. Suggested command: pip install faster-whisper"
}

if (-not (Test-Path -LiteralPath $MediaFile)) {
    throw "Media file not found: $MediaFile"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($MediaFile)
    $OutputFile = Join-Path ([System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $MediaFile).Path)) "$base.transcript.md"
}

$script = @"
from faster_whisper import WhisperModel
from pathlib import Path

media = Path(r'''$MediaFile''')
output = Path(r'''$OutputFile''')
model = WhisperModel(r'''$Model''', device='auto', compute_type='auto')
segments, info = model.transcribe(str(media), language=r'''$Language''')

lines = []
lines.append(f"# Transcript: {media.name}")
lines.append("")
lines.append(f"- Language: {info.language}")
lines.append(f"- Duration: {info.duration}")
lines.append("")
for segment in segments:
    lines.append(f"[{segment.start:.2f} - {segment.end:.2f}] {segment.text.strip()}")

output.write_text("\n".join(lines), encoding="utf-8")
print(output)
"@

$tmp = Join-Path $env:TEMP "obsidian-feishu-transcribe-$([guid]::NewGuid().ToString()).py"
Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
try {
    & python $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "faster-whisper transcription failed."
    }
} finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Write-Host "Transcript written to $OutputFile"

