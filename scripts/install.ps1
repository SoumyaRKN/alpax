# Alpax (अल्प) Universal 1-Click Installer for Windows (PowerShell)
# Run with: powershell -ExecutionPolicy Bypass -File scripts\install.ps1

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "          Alpax (अल्प) Universal Windows Installer" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$AppDir = Join-Path $env:LOCALAPPDATA "alpax"
$ModelsDir = Join-Path $AppDir "models"
$BinDir = Join-Path $AppDir "bin"

New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalBinary = Join-Path (Split-Path -Parent $ScriptDir) "target\release\alpax.exe"
$TargetBin = Join-Path $BinDir "alpax.exe"

if (Test-Path $LocalBinary) {
    Write-Host "📦 Installing alpax binary to $TargetBin..." -ForegroundColor Green
    Copy-Item -Path $LocalBinary -Destination $TargetBin -Force
} else {
    Write-Host "Building release binary via cargo..." -ForegroundColor Yellow
    cargo build --release
    Copy-Item -Path $LocalBinary -Destination $TargetBin -Force
}

$ModelFile = Join-Path $ModelsDir "all-MiniLM-L6-v2.onnx"
$TokenizerFile = Join-Path $ModelsDir "tokenizer.json"

$ModelUrl = "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
$TokenizerUrl = "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

if (-not (Test-Path $ModelFile)) {
    Write-Host "⬇ Downloading lightweight AI model (~22MB)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ModelUrl -OutFile $ModelFile
}

if (-not (Test-Path $TokenizerFile)) {
    Write-Host "⬇ Downloading tokenizer file (~450KB)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $TokenizerUrl -OutFile $TokenizerFile
}

# Auto-configure Claude Desktop on Windows
$ClaudeConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
if (Test-Path (Split-Path -Parent $ClaudeConfig)) {
    try {
        $ConfigJson = @{}
        if (Test-Path $ClaudeConfig) {
            $ConfigJson = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json -AsHashtable
        }
        if (-not $ConfigJson.ContainsKey("mcpServers")) {
            $ConfigJson["mcpServers"] = @{}
        }
        $ConfigJson["mcpServers"]["alpax"] = @{
            command = $TargetBin
            args = @()
        }
        $ConfigJson | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig -Encoding UTF8
        Write-Host "✓ Automatically configured Claude Desktop at $ClaudeConfig" -ForegroundColor Green
    } catch {
        Write-Host "Notice: Could not automatically update Claude Desktop config: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🎉 Alpax installation completed successfully!" -ForegroundColor Green
Write-Host "Binary location: $TargetBin" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
