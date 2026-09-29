# =============================================================================
# Alpax (अल्प) — Universal Windows Installer (PowerShell)
# =============================================================================
# USAGE (one-liner, as shown in README — run in PowerShell):
#   irm https://raw.githubusercontent.com/sourceround/alpax/main/scripts/install.ps1 | iex
#
# Or download and run manually:
#   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/sourceround/alpax/main/scripts/install.ps1" -OutFile install.ps1
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
    Write-Host "`n[$n/6] $msg" -ForegroundColor Yellow -NoNewline; Write-Host "" }

function Ask-WithDefault {
    param([string]$Question, [string]$Default)
    if ($Yes) { return $Default }
    $answer = Read-Host "    $Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer
}

function Confirm-Action {
    param([string]$Prompt)
    if ($Yes) { return $true }
    $answer = Read-Host "    $Prompt [Y/n]"
    return ($answer -eq "" -or $answer -match '^[Yy]')
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

$Repo = "sourceround/alpax"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

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

# Determine install directories
$AppDir  = if ($Prefix) { $Prefix } else { Join-Path $env:LOCALAPPDATA "alpax" }
$BinDir  = Join-Path $AppDir "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$TmpDir = Join-Path $env:TEMP "alpax-install-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

Write-Info "Downloading $ArchiveName..."
$ArchivePath = Join-Path $TmpDir $ArchiveName
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Err "Download failed: $DownloadUrl"
    Write-Err "Make sure a GitHub Release exists for tag $LatestTag."
    Write-Err "If you have Rust installed, run: cargo install --git https://github.com/$Repo alpax"
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Info "Extracting binary..."
Expand-Archive -Path $ArchivePath -DestinationPath $TmpDir -Force
$BinarySrc = Get-ChildItem -Recurse -Path $TmpDir -Filter "alpax.exe" | Select-Object -First 1
if (-not $BinarySrc) {
    Write-Err "Could not find alpax.exe in the downloaded archive."
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$TargetBin = Join-Path $BinDir "alpax.exe"
Copy-Item -Path $BinarySrc.FullName -Destination $TargetBin -Force
Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Ok "Binary installed → $TargetBin"

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

# ── Step 5: Detect & configure AI coding agents ───────────────────────────────
Write-Step 5 "Detecting installed AI coding agents"

# JSON upsert helper — merges {"mcpServers":{"alpax":{...}}} into existing JSON
function Upsert-McpJson {
    param(
        [string]$ConfigPath,
        [string]$ServersKey,
        [string]$ServerName,
        [string]$CommandPath
    )
    $dir = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $data = @{}
    if (Test-Path $ConfigPath) {
        try {
            $raw = Get-Content $ConfigPath -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json -AsHashtable
        } catch { $data = @{} }
    }
    if (-not $data.ContainsKey($ServersKey) -or $null -eq $data[$ServersKey]) {
        $data[$ServersKey] = @{}
    }
    $data[$ServersKey][$ServerName] = @{ command = $CommandPath; args = @() }
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
    return $true
}

# Zed context_servers format
function Upsert-ZedJson {
    param([string]$ConfigPath, [string]$CommandPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
    $data = @{}
    if (Test-Path $ConfigPath) {
        try { $data = (Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable) } catch {}
    }
    if (-not $data.ContainsKey("context_servers")) { $data["context_servers"] = @{} }
    $data["context_servers"]["alpax"] = @{
        command  = @{ path = $CommandPath; args = @() }
        settings = @{}
    }
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
    return $true
}

$AgentsFound        = [System.Collections.Generic.List[string]]::new()
$AgentsConfigured   = [System.Collections.Generic.List[string]]::new()
$AgentsSkipped      = [System.Collections.Generic.List[string]]::new()

function Try-Configure {
    param(
        [string]$Label,
        [string]$ConfigPath,
        [string]$ServersKey,
        [string]$ServerName,
        [string]$CommandPath
    )
    Write-Info "Found: $Label"
    $AgentsFound.Add($Label)
    if (Confirm-Action "  Configure $Label to use Alpax?") {
        try {
            Upsert-McpJson -ConfigPath $ConfigPath -ServersKey $ServersKey `
                           -ServerName $ServerName -CommandPath $CommandPath | Out-Null
            Write-Ok "$Label configured → $ConfigPath"
            $AgentsConfigured.Add($Label)
        } catch {
            Write-Warn "$Label config update failed: $_"
            $AgentsSkipped.Add($Label)
        }
    } else {
        Write-Info "Skipped $Label"
        $AgentsSkipped.Add($Label)
    }
}

# ── 1. Claude Desktop ─────────────────────────────────────────────────────────
$ClaudeDesktopConf = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$ClaudeDesktopDir  = Join-Path $env:APPDATA "Claude"
if ((Test-Path $ClaudeDesktopDir) -or (Test-Path $ClaudeDesktopConf)) {
    Try-Configure "Claude Desktop" $ClaudeDesktopConf "mcpServers" "alpax" $TargetBin
}

# ── 2. Claude Code CLI ────────────────────────────────────────────────────────
$ClaudeCliConf = Join-Path $env:USERPROFILE ".claude.json"
$ClaudeCliDir  = Join-Path $env:USERPROFILE ".claude"
if ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path $ClaudeCliDir) -or (Test-Path $ClaudeCliConf)) {
    Try-Configure "Claude Code CLI" $ClaudeCliConf "mcpServers" "alpax" $TargetBin
}

# ── 3. Cursor IDE ─────────────────────────────────────────────────────────────
$CursorMcp = Join-Path $env:USERPROFILE ".cursor\mcp.json"
$CursorDir  = Join-Path $env:USERPROFILE ".cursor"
$CursorApp  = Join-Path $env:LOCALAPPDATA "Programs\cursor\Cursor.exe"
if ((Get-Command cursor -ErrorAction SilentlyContinue) -or (Test-Path $CursorDir) -or (Test-Path $CursorApp)) {
    Try-Configure "Cursor IDE" $CursorMcp "mcpServers" "alpax" $TargetBin
}

# ── 4. Windsurf IDE ───────────────────────────────────────────────────────────
$WindsurfMcp = Join-Path $env:USERPROFILE ".codeium\windsurf\mcp_config.json"
$WindsurfDir = Join-Path $env:USERPROFILE ".codeium\windsurf"
$WindsurfApp = Join-Path $env:LOCALAPPDATA "Programs\Windsurf\Windsurf.exe"
if ((Get-Command windsurf -ErrorAction SilentlyContinue) -or (Test-Path $WindsurfDir) -or (Test-Path $WindsurfApp)) {
    Try-Configure "Windsurf IDE" $WindsurfMcp "mcpServers" "alpax" $TargetBin
}

# ── 5. VS Code + Continue extension ──────────────────────────────────────────
$ContinueConf = Join-Path $env:USERPROFILE ".continue\config.json"
$ContinueDir  = Join-Path $env:USERPROFILE ".continue"
if ((Test-Path $ContinueDir) -or (Test-Path $ContinueConf)) {
    Try-Configure "VS Code / Continue extension" $ContinueConf "mcpServers" "alpax" $TargetBin
}

# ── 6. VS Code + Cline extension ─────────────────────────────────────────────
$VsCodeStorage = Join-Path $env:APPDATA "Code\User\globalStorage"
$ClineMcp = Join-Path $env:USERPROFILE ".cline\mcp_settings.json"
if (Test-Path $VsCodeStorage) {
    $ClineExt = Join-Path $VsCodeStorage "saoudrizwan.claude-dev\settings\cline_mcp_settings.json"
    if (Test-Path (Split-Path -Parent $ClineExt)) { $ClineMcp = $ClineExt }
}
if (Test-Path (Split-Path -Parent $ClineMcp) -ErrorAction SilentlyContinue) {
    Try-Configure "VS Code / Cline extension" $ClineMcp "mcpServers" "alpax" $TargetBin
}

# ── 7. VS Code + Roo Code extension ──────────────────────────────────────────
$RooMcp = Join-Path $env:USERPROFILE ".roo\mcp.json"
if (Test-Path $VsCodeStorage) {
    $RooExt = Join-Path $VsCodeStorage "rooveterinaryinc.roo-cline\settings\mcp.json"
    if (Test-Path (Split-Path -Parent $RooExt)) { $RooMcp = $RooExt }
}
if (Test-Path (Split-Path -Parent $RooMcp) -ErrorAction SilentlyContinue) {
    Try-Configure "VS Code / Roo Code extension" $RooMcp "mcpServers" "alpax" $TargetBin
}

# ── 8. Zed editor ─────────────────────────────────────────────────────────────
$ZedConf = Join-Path $env:APPDATA "Zed\settings.json"
$ZedApp  = Join-Path $env:LOCALAPPDATA "Programs\Zed\zed.exe"
if ((Get-Command zed -ErrorAction SilentlyContinue) -or (Test-Path $ZedApp) -or (Test-Path $ZedConf)) {
    Write-Info "Found: Zed editor"
    $AgentsFound.Add("Zed")
    if (Confirm-Action "  Configure Zed to use Alpax?") {
        try {
            Upsert-ZedJson -ConfigPath $ZedConf -CommandPath $TargetBin | Out-Null
            Write-Ok "Zed configured → $ZedConf"
            $AgentsConfigured.Add("Zed")
        } catch {
            Write-Warn "Zed config update failed: $_"
            $AgentsSkipped.Add("Zed")
        }
    } else { $AgentsSkipped.Add("Zed") }
}

# ── 9. Antigravity CLI ────────────────────────────────────────────────────────
# Global MCP config: ~/.gemini/config/mcp_config.json
# Schema: { "mcpServers": { "<name>": { "command": "...", "args": [], "env": {} } } }
# Ref: ~/.gemini/antigravity-cli/builtin/skills/agy-customizations/docs/mcp_servers.md
$AgyConfigDir = Join-Path $env:USERPROFILE ".gemini\config"
$AgyMcpConf   = Join-Path $AgyConfigDir "mcp_config.json"
$AgyCliDir    = Join-Path $env:USERPROFILE ".gemini\antigravity-cli"
if ((Get-Command agy -ErrorAction SilentlyContinue) -or (Test-Path $AgyConfigDir) -or (Test-Path $AgyCliDir)) {
    Try-Configure "Antigravity CLI (agy)" $AgyMcpConf "mcpServers" "alpax" $TargetBin
}

if ($AgentsFound.Count -eq 0) {
    Write-Warn "No AI coding agents detected on this system."
    Write-Info "After installing one, re-run this installer or add the config manually (see below)."
}

# ── Step 6: PATH ──────────────────────────────────────────────────────────────
Write-Step 6 "Finalising PATH"

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

if ($AgentsConfigured.Count -gt 0) {
    Write-Host "  Configured agents:" -ForegroundColor Green
    foreach ($a in $AgentsConfigured) { Write-Host "    ✓  $a" -ForegroundColor Green }
}
if ($AgentsSkipped.Count -gt 0) {
    Write-Host "  Skipped agents:" -ForegroundColor Yellow
    foreach ($a in $AgentsSkipped) { Write-Host "    ○  $a" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "  How to use Alpax:" -ForegroundColor White
Write-Host "    Open any configured AI agent and ask:"
Write-Host '    "Where is the authentication logic in this codebase?"' -ForegroundColor Cyan
Write-Host "    Alpax indexes your project automatically on first use."
Write-Host ""

if ($AgentsConfigured.Count -gt 0) {
    Write-Host "  Restart your AI agent(s) for the changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Manual MCP config snippet (for any agent that supports MCP):"
Write-Host '  {'
Write-Host '    "mcpServers": {'
Write-Host "      `"alpax`": { `"command`": `"$TargetBin`" }"
Write-Host '    }'
Write-Host '  }'
Write-Host ""
