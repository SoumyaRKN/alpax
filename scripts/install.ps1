# =============================================================================
# Alpax (अल्प) — Universal Windows Installer (PowerShell)
# =============================================================================
# USAGE (one-liner, as shown in README — run in PowerShell):
#   irm https://raw.githubusercontent.com/SoumyaRKN/alpax/main/scripts/install.ps1 | iex
#
# Or download and run manually:
#   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SoumyaRKN/alpax/main/scripts/install.ps1" -OutFile install.ps1
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Flags:
#   -Yes          Accept all defaults non-interactively
#   -Prefix <dir> Custom binary installation directory
# =============================================================================
param(
    [switch]$Yes,
    [string]$Prefix = ""
)

$ErrorActionPreference = "Stop"

# ── Colours ───────────────────────────────────────────────────────────────────
function Write-Header { param([string]$msg)
    Write-Host "`n━━━  $msg  ━━━" -ForegroundColor Cyan }
function Write-Ok     { param([string]$msg)
    Write-Host "  ✓  $msg" -ForegroundColor Green }
function Write-Info   { param([string]$msg)
    Write-Host "  →  $msg" -ForegroundColor Blue }
function Write-Warn   { param([string]$msg)
    Write-Host "  ⚠  $msg" -ForegroundColor Yellow }
function Write-Err    { param([string]$msg)
    Write-Host "  ✗  $msg" -ForegroundColor Red }
function Write-Step   { param([int]$n, [string]$msg)
    Write-Host "`n[$n/5] $msg" -ForegroundColor Yellow -NoNewline; Write-Host "" }

function Ask-WithDefault {
    param([string]$Question, [string]$Default)
    if ($Yes) { return $Default }
    $answer = Read-Host "    $Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         Alpax (अल्प) — Windows Installer             ║" -ForegroundColor Cyan
Write-Host "  ║  Ultra-lightweight local-first Code Vectorizer MCP   ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Detect architecture ──────────────────────────────────────────────
Write-Step 1 "Detecting your platform"

$Arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) { "arm64" } else { "x86_64" }
$Platform = "windows-$Arch"
Write-Ok "Detected: Windows $Arch → artifact suffix: $Platform"

# ── Step 2: Download binary ───────────────────────────────────────────────────
Write-Step 2 "Downloading Alpax binary"

$Repo = "SoumyaRKN/alpax"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

# Determine install directories
$AppDir  = if ($Prefix) { $Prefix } else { Join-Path $env:LOCALAPPDATA "alpax" }
$BinDir  = Join-Path $AppDir "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$TargetBin = Join-Path $BinDir "alpax.exe"

$BinaryInstalled = $false

# Check for local build first
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ScriptDir) {
    $LocalRel = Join-Path $ScriptDir "..\target\release\alpax.exe"
    if (Test-Path $LocalRel) {
        Write-Info "Found local release binary: $LocalRel"
        Copy-Item -Path $LocalRel -Destination $TargetBin -Force
        $BinaryInstalled = $true
        Write-Ok "Binary installed from local build → $TargetBin"
    }
}

if (-not $BinaryInstalled) {
    Write-Info "Fetching latest release from GitHub..."
    try {
        $ReleaseInfo = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing -ErrorAction Stop
        $LatestTag   = $ReleaseInfo.tag_name
    } catch {
        $LatestTag = "v1.0.0"
        Write-Warn "Could not fetch latest tag — defaulting to $LatestTag"
    }
    Write-Ok "Latest release: $LatestTag"

    $ArchiveName = "alpax-$LatestTag-$Platform.zip"
    $DownloadUrl = "https://github.com/$Repo/releases/download/$LatestTag/$ArchiveName"

    $TmpDir = Join-Path $env:TEMP "alpax-install-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
    $ArchivePath = Join-Path $TmpDir $ArchiveName

    Write-Info "Downloading $ArchiveName..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath -UseBasicParsing -ErrorAction Stop
        Write-Info "Extracting binary..."
        Expand-Archive -Path $ArchivePath -DestinationPath $TmpDir -Force
        $BinarySrc = Get-ChildItem -Recurse -Path $TmpDir -Filter "alpax.exe" | Select-Object -First 1
        if ($BinarySrc) {
            Copy-Item -Path $BinarySrc.FullName -Destination $TargetBin -Force
            $BinaryInstalled = $true
            Write-Ok "Binary installed → $TargetBin"
        }
    } catch {
        Write-Warn "Download failed: $DownloadUrl"
    } finally {
        Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $BinaryInstalled) {
    $ExistingCmd = Get-Command alpax.exe -ErrorAction SilentlyContinue
    if ($ExistingCmd) {
        Copy-Item -Path $ExistingCmd.Source -Destination $TargetBin -Force
        $BinaryInstalled = $true
        Write-Ok "Reusing existing alpax.exe → $TargetBin"
    } else {
        Write-Err "Could not install alpax binary. If you have Rust installed, run:"
        Write-Err "  cargo build --release"
        exit 1
    }
}

# ── Step 3: Configuration ─────────────────────────────────────────────────────
Write-Step 3 "Configuration"

$AlpaxHome   = Join-Path $env:LOCALAPPDATA "alpax"
$ModelsDir   = Join-Path $AlpaxHome "models"
$DbDir       = Join-Path $AlpaxHome "db"
$GlobalConf  = Join-Path $AlpaxHome "alpax.toml"

Write-Host ""
Write-Host "  All settings have sensible defaults. Press Enter to accept them." -ForegroundColor DarkGray
Write-Host "  You can change any setting later by editing: $GlobalConf" -ForegroundColor DarkGray
Write-Host ""

$CfgBinDir      = Ask-WithDefault "Binary install directory" $BinDir
$CfgAlpaxHome   = Ask-WithDefault "Data directory (models, DB, config)" $AlpaxHome
$CfgChunkSize   = Ask-WithDefault "Chunk size (lines per code snippet)" "50"
$CfgOverlap     = Ask-WithDefault "Chunk overlap (shared lines)" "10"

# Normalise
$AlpaxHome = $CfgAlpaxHome
$ModelsDir = Join-Path $AlpaxHome "models"
$DbDir     = Join-Path $AlpaxHome "db"
$GlobalConf = Join-Path $AlpaxHome "alpax.toml"
New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null
New-Item -ItemType Directory -Force -Path $DbDir     | Out-Null

if ($CfgBinDir -ne $BinDir) {
    New-Item -ItemType Directory -Force -Path $CfgBinDir | Out-Null
    Copy-Item -Path $TargetBin -Destination (Join-Path $CfgBinDir "alpax.exe") -Force
    $TargetBin = Join-Path $CfgBinDir "alpax.exe"
    $BinDir    = $CfgBinDir
}

if (-not ($CfgChunkSize -match '^\d+$') -or [int]$CfgChunkSize -lt 1) { $CfgChunkSize = "50" }
if (-not ($CfgOverlap   -match '^\d+$'))                               { $CfgOverlap   = "10" }

Write-Ok "Configuration accepted"

# ── Step 4: Download models ───────────────────────────────────────────────────
Write-Step 4 "Downloading AI embedding models"

$ModelFile     = Join-Path $ModelsDir "all-MiniLM-L6-v2.onnx"
$TokenizerFile = Join-Path $ModelsDir "tokenizer.json"
$ModelUrl      = "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
$TokenizerUrl  = "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

function Download-Asset {
    param([string]$Url, [string]$Dest, [string]$Label)
    if (Test-Path $Dest) { Write-Ok "$Label already present — skipping"; return }
    Write-Info "Downloading $Label..."
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    Write-Ok "$Label downloaded"
}

Download-Asset $ModelUrl     $ModelFile     "Embedding model (INT8 ONNX, ~22 MB)"
Download-Asset $TokenizerUrl $TokenizerFile "Tokenizer (~450 KB)"

# Write global config (forward-slash paths work fine in Rust)
$ModelFileF     = $ModelFile.Replace('\','/')
$TokenizerFileF = $TokenizerFile.Replace('\','/')
$DbDirF         = $DbDir.Replace('\','/')
$Timestamp      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

@"
# Alpax (अल्प) — Global Configuration
# Generated: $Timestamp
# Docs:      https://github.com/$Repo#configuration
#
# This file sets your global defaults.
# Drop an alpax.toml in any project root to override per-project.

model         = "$ModelFileF"
tokenizer     = "$TokenizerFileF"
db            = "$DbDirF"
chunk_size    = $CfgChunkSize
chunk_overlap = $CfgOverlap
"@ | Set-Content -Path $GlobalConf -Encoding UTF8

Write-Ok "Global config → $GlobalConf"

# ── Step 5: PATH ──────────────────────────────────────────────────────────────
Write-Step 5 "Finalising PATH"

$CurrentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($CurrentPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$BinDir;$CurrentPath", "User")
    Write-Ok "Added $BinDir to your user PATH (restart terminal to apply)"
} else {
    Write-Ok "PATH already contains $BinDir"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║          🎉  Alpax is installed and ready!           ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Binary:     $TargetBin"
Write-Host "  Models:     $ModelsDir"
Write-Host "  Config:     $GlobalConf"
Write-Host "  Vector DB:  $DbDir  (auto-created per project)"
Write-Host ""

$EscapedBin = $TargetBin.Replace('\', '\\')

Write-Host "━━━  AI Coding Agent Configuration  ━━━" -ForegroundColor Cyan
Write-Host "  Alpax works with any Model Context Protocol (MCP) compatible agent."
Write-Host "  Please add Alpax to your agent's MCP configuration:"
Write-Host ""
Write-Host "  Standard MCP Configuration (JSON):" -ForegroundColor White
Write-Host "  {"
Write-Host '    "mcpServers": {'
Write-Host "      `"alpax`": {"
Write-Host "        `"command`": `"$EscapedBin`""
Write-Host "      }"
Write-Host "    }"
Write-Host "  }"
Write-Host ""
Write-Host "  Common Windows Agent Configuration File Paths:" -ForegroundColor White
Write-Host "    • Antigravity CLI (agy)     $env:USERPROFILE\.gemini\config\mcp_config.json"
Write-Host "    • Claude Desktop            $env:APPDATA\Claude\claude_desktop_config.json"
Write-Host "    • Claude Code CLI           $env:USERPROFILE\.claude.json"
Write-Host "    • Cursor IDE                $env:USERPROFILE\.cursor\mcp.json"
Write-Host "    • Windsurf IDE              $env:USERPROFILE\.codeium\windsurf\mcp_config.json"
Write-Host "    • VS Code (Cline)           $env:USERPROFILE\.cline\mcp_settings.json"
Write-Host "    • VS Code (Roo Code)        $env:USERPROFILE\.roo\mcp.json"
Write-Host "    • VS Code (Continue)        $env:USERPROFILE\.continue\config.json"
Write-Host "    • Zed Editor                $env:APPDATA\Zed\settings.json"
Write-Host ""
Write-Host "  After adding the configuration, restart your AI agent to apply." -ForegroundColor Yellow
Write-Host ""
