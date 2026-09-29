#!/usr/bin/env bash
# =============================================================================
# Alpax (अल्प) — Universal Installer
# =============================================================================
# USAGE (one-liner, as shown in README):
#   curl -fsSL https://raw.githubusercontent.com/sourceround/alpax/main/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL .../install.sh | bash -s -- --yes          # non-interactive (accept all defaults)
#   curl -fsSL .../install.sh | bash -s -- --prefix /opt  # custom install prefix
#
# WHAT THIS SCRIPT DOES:
#   1. Detects your OS and CPU architecture
#   2. Downloads the correct pre-built alpax binary from GitHub Releases
#   3. Asks a few configuration questions (with sensible defaults — just press Enter)
#   4. Downloads the AI embedding model (~22 MB) and tokenizer to ~/.alpax/models/
#   5. Writes your config to ~/.alpax/alpax.toml
#   6. Scans for ALL installed AI coding agents and safely updates their MCP configs
#   7. Adds alpax to your PATH
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
    RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; BLUE="\033[34m"
else
    BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; BLUE=""
fi

log_header() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${RESET}"; }
log_ok()     { echo -e "  ${GREEN}✓${RESET}  $*"; }
log_info()   { echo -e "  ${BLUE}→${RESET}  $*"; }
log_warn()   { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_err()    { echo -e "  ${RED}✗${RESET}  $*" >&2; }
log_step()   { echo -e "\n${BOLD}${YELLOW}[$1/6]${RESET} $2"; }

# ── Parse flags ──────────────────────────────────────────────────────────────
NON_INTERACTIVE=false
CUSTOM_PREFIX=""
for arg in "$@"; do
    case "$arg" in
        --yes|-y)      NON_INTERACTIVE=true ;;
        --prefix=*)    CUSTOM_PREFIX="${arg#--prefix=}" ;;
        --prefix)      shift; CUSTOM_PREFIX="${1:-}" ;;
    esac
done

ask() {
    # ask <prompt> <default> <varname>
    local prompt="$1" default="$2" varname="$3"
    if $NON_INTERACTIVE; then
        printf -v "$varname" "%s" "$default"
        return
    fi
    local answer
    printf "    %s [%s]: " "$prompt" "$default"
    read -r answer </dev/tty
    printf -v "$varname" "%s" "${answer:-$default}"
}

confirm() {
    # confirm <prompt>  → returns 0 (yes) or 1 (no)
    if $NON_INTERACTIVE; then return 0; fi
    local answer
    printf "    %s [Y/n]: " "$1"
    read -r answer </dev/tty
    case "${answer:-y}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║         Alpax (अल्प) — Installer                       ║"
echo "  ║  Ultra-lightweight local-first Code Vectorizer MCP    ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Detect platform ───────────────────────────────────────────────────
log_step 1 "Detecting your platform"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)  PLATFORM_OS="linux" ;;
    Darwin) PLATFORM_OS="macos" ;;
    *)
        log_err "Unsupported OS: $OS"
        log_err "For Windows, open PowerShell and run:"
        log_err "  irm https://raw.githubusercontent.com/sourceround/alpax/main/scripts/install.ps1 | iex"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)  PLATFORM_ARCH="x86_64" ;;
    aarch64|arm64) PLATFORM_ARCH="arm64" ;;
    *)
        log_err "Unsupported CPU architecture: $ARCH"
        exit 1
        ;;
esac

PLATFORM="${PLATFORM_OS}-${PLATFORM_ARCH}"
log_ok "Detected: ${BOLD}${OS}${RESET} on ${BOLD}${ARCH}${RESET} → artifact suffix: ${DIM}${PLATFORM}${RESET}"

# ── Step 2: Download binary ───────────────────────────────────────────────────
log_step 2 "Downloading Alpax binary"

REPO="sourceround/alpax"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"

# Resolve latest release tag
if command -v curl >/dev/null 2>&1; then
    _dl() { curl -fsSL "$1" -o "$2"; }
    _fetch() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
    _dl() { wget -q "$1" -O "$2"; }
    _fetch() { wget -q -O- "$1"; }
else
    log_err "Neither curl nor wget found. Please install one and re-run."
    exit 1
fi

log_info "Fetching latest release information from GitHub..."
LATEST_TAG=$(_fetch "${GITHUB_API}" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tag_name'])" 2>/dev/null || true)

if [ -z "${LATEST_TAG}" ]; then
    log_warn "Could not fetch latest release tag — defaulting to 'v1.0.0'"
    LATEST_TAG="v1.0.0"
fi
log_ok "Latest release: ${BOLD}${LATEST_TAG}${RESET}"

# Construct artifact URL
ARCHIVE_NAME="alpax-${LATEST_TAG}-${PLATFORM}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ARCHIVE_NAME}"

# Determine install prefix
if [ -n "${CUSTOM_PREFIX}" ]; then
    BIN_DIR="${CUSTOM_PREFIX}/bin"
else
    BIN_DIR="${HOME}/.local/bin"
fi
mkdir -p "${BIN_DIR}"

# Download and extract
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

log_info "Downloading ${ARCHIVE_NAME}..."
if ! _dl "${DOWNLOAD_URL}" "${TMPDIR_WORK}/${ARCHIVE_NAME}" 2>/dev/null; then
    log_err "Download failed: ${DOWNLOAD_URL}"
    log_err "This may mean no release has been published yet."
    log_err ""
    log_err "If you have Rust installed, run: cargo install --git https://github.com/${REPO} alpax"
    exit 1
fi

log_info "Extracting binary..."
tar xzf "${TMPDIR_WORK}/${ARCHIVE_NAME}" -C "${TMPDIR_WORK}"
BINARY_SRC="$(find "${TMPDIR_WORK}" -name "alpax" -type f | head -1)"
if [ -z "${BINARY_SRC}" ]; then
    log_err "Could not find 'alpax' binary in the downloaded archive."
    exit 1
fi

cp -f "${BINARY_SRC}" "${BIN_DIR}/alpax"
chmod +x "${BIN_DIR}/alpax"
export PATH="${BIN_DIR}:${PATH}"
log_ok "Binary installed → ${BOLD}${BIN_DIR}/alpax${RESET}"

# ── Step 3: Configuration ─────────────────────────────────────────────────────
log_step 3 "Configuration"

ALPAX_HOME="${HOME}/.alpax"
MODELS_DIR="${ALPAX_HOME}/models"
DB_DIR="${ALPAX_HOME}/db"
GLOBAL_CONFIG="${ALPAX_HOME}/alpax.toml"

mkdir -p "${MODELS_DIR}" "${DB_DIR}"

echo ""
echo -e "  ${DIM}All settings have sensible defaults. Press ${BOLD}Enter${RESET}${DIM} to accept them.${RESET}"
echo -e "  ${DIM}You can change any setting later by editing: ${GLOBAL_CONFIG}${RESET}"
echo ""

ask "Installation directory for binary" "${BIN_DIR}"     _BIN_DIR
ask "Data directory (models, DB, config)" "${ALPAX_HOME}" _ALPAX_HOME
ask "Chunk size — lines per code snippet"  "50"           CFG_CHUNK_SIZE
ask "Chunk overlap — shared lines"         "10"           CFG_OVERLAP

# Apply user-provided overrides
BIN_DIR="${_BIN_DIR}"
ALPAX_HOME="${_ALPAX_HOME}"
MODELS_DIR="${ALPAX_HOME}/models"
DB_DIR="${ALPAX_HOME}/db"
GLOBAL_CONFIG="${ALPAX_HOME}/alpax.toml"
mkdir -p "${MODELS_DIR}" "${DB_DIR}" "${BIN_DIR}"

# Move binary if path changed
if [ ! -f "${BIN_DIR}/alpax" ] || [ "${BIN_DIR}/alpax" != "$(which alpax 2>/dev/null || true)" ]; then
    cp -f "$(which alpax 2>/dev/null || echo "${HOME}/.local/bin/alpax")" "${BIN_DIR}/alpax" 2>/dev/null || true
    chmod +x "${BIN_DIR}/alpax"
fi

# Validate numerics
[[ "${CFG_CHUNK_SIZE}" =~ ^[1-9][0-9]*$ ]] || { log_warn "Invalid chunk size, using 50"; CFG_CHUNK_SIZE=50; }
[[ "${CFG_OVERLAP}" =~ ^[0-9]+$ ]]          || { log_warn "Invalid overlap, using 10";    CFG_OVERLAP=10; }

log_ok "Configuration accepted"

# ── Step 4: Download models ───────────────────────────────────────────────────
log_step 4 "Downloading AI embedding models"

MODEL_FILE="${MODELS_DIR}/all-MiniLM-L6-v2.onnx"
TOKENIZER_FILE="${MODELS_DIR}/tokenizer.json"
MODEL_URL="https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

_download_asset() {
    local url="$1" dest="$2" label="$3"
    if [ -f "${dest}" ]; then
        log_ok "${label} already present — skipping"
        return
    fi
    log_info "Downloading ${label}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${url}" -o "${dest}" 2>&1 | sed 's/^/    /'
    else
        wget -q --show-progress "${url}" -O "${dest}" 2>&1 | sed 's/^/    /'
    fi
    log_ok "${label} downloaded"
}

_download_asset "${MODEL_URL}"     "${MODEL_FILE}"     "Embedding model (INT8 ONNX, ~22 MB)"
_download_asset "${TOKENIZER_URL}" "${TOKENIZER_FILE}" "Tokenizer (~450 KB)"

# Write global config
cat > "${GLOBAL_CONFIG}" <<TOML
# Alpax (अल्प) — Global Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Docs:      https://github.com/${REPO}#configuration
#
# This file sets your global defaults.
# Drop an alpax.toml in any project root to override per-project.

model         = "${MODEL_FILE}"
tokenizer     = "${TOKENIZER_FILE}"
db            = "${DB_DIR}"
chunk_size    = ${CFG_CHUNK_SIZE}
chunk_overlap = ${CFG_OVERLAP}
TOML
log_ok "Global config → ${BOLD}${GLOBAL_CONFIG}${RESET}"

# ── Step 5: Detect & configure AI coding agents ───────────────────────────────
log_step 5 "Detecting installed AI coding agents"

# JSON upsert helper: safely merges {"mcpServers":{"alpax":{...}}} into existing JSON
# Usage: _upsert_mcp_json <config_file> <key_path> <server_name> <command>
# key_path: dot-separated path to the mcpServers object, e.g. "mcpServers" or "settings.mcpServers"
_upsert_mcp_json() {
    local config_file="$1"
    local servers_key="$2"   # e.g. "mcpServers"
    local server_name="$3"
    local command_path="$4"
    local extra_args="${5:-}"

    python3 - <<PYEOF
import json, os, sys

config_path = '${config_file}'
servers_key = '${servers_key}'
server_name = '${server_name}'
cmd         = '${command_path}'
extra       = '${extra_args}'

# Load or create
if os.path.exists(config_path):
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError):
        data = {}
else:
    data = {}

# Navigate / create the servers dict (supports simple single-level key only)
if servers_key not in data or not isinstance(data[servers_key], dict):
    data[servers_key] = {}

entry = {'command': cmd, 'args': []}
if extra:
    entry['args'] = extra.split()

data[servers_key][server_name] = entry

os.makedirs(os.path.dirname(os.path.abspath(config_path)), exist_ok=True)
with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('ok')
PYEOF
}

# Zed uses "context_servers" with a different schema
_upsert_zed_json() {
    local config_file="$1"
    local command_path="$2"

    python3 - <<PYEOF
import json, os

config_path = '${config_file}'
cmd         = '${command_path}'

if os.path.exists(config_path):
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError):
        data = {}
else:
    data = {}

data.setdefault('context_servers', {})['alpax'] = {
    'command': {'path': cmd, 'args': []},
    'settings': {}
}

os.makedirs(os.path.dirname(os.path.abspath(config_path)), exist_ok=True)
with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('ok')
PYEOF
}

ALPAX_BIN="${BIN_DIR}/alpax"
AGENTS_FOUND=()
AGENTS_CONFIGURED=()
AGENTS_SKIPPED=()

# ── Helper: try to configure an agent ────────────────────────────────────────
_try_configure() {
    local agent_label="$1"
    local config_path="$2"
    local servers_key="$3"
    local server_name="$4"
    local command_path="$5"

    log_info "Found: ${BOLD}${agent_label}${RESET}"
    AGENTS_FOUND+=("${agent_label}")

    if confirm "  Configure ${agent_label} to use Alpax?"; then
        local result
        result=$(_upsert_mcp_json "${config_path}" "${servers_key}" "${server_name}" "${command_path}" 2>&1)
        if [ "${result}" = "ok" ]; then
            log_ok "${agent_label} configured → ${DIM}${config_path}${RESET}"
            AGENTS_CONFIGURED+=("${agent_label}")
        else
            log_warn "${agent_label} config update failed: ${result}"
            AGENTS_SKIPPED+=("${agent_label}")
        fi
    else
        log_info "Skipped ${agent_label}"
        AGENTS_SKIPPED+=("${agent_label}")
    fi
}

_try_configure_zed() {
    local config_path="$1"
    log_info "Found: ${BOLD}Zed${RESET}"
    AGENTS_FOUND+=("Zed")
    if confirm "  Configure Zed to use Alpax?"; then
        local result
        result=$(_upsert_zed_json "${config_path}" "${ALPAX_BIN}" 2>&1)
        if [ "${result}" = "ok" ]; then
            log_ok "Zed configured → ${DIM}${config_path}${RESET}"
            AGENTS_CONFIGURED+=("Zed")
        else
            log_warn "Zed config update failed: ${result}"
            AGENTS_SKIPPED+=("Zed")
        fi
    else
        log_info "Skipped Zed"
        AGENTS_SKIPPED+=("Zed")
    fi
}

# Check if python3 is available (required for JSON updates)
if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not found — cannot auto-configure MCP clients."
    log_warn "After install, add alpax manually (see README for JSON snippets)."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 1. CLAUDE DESKTOP (standalone app)
# ──────────────────────────────────────────────────────────────────────────────
if [ "$PLATFORM_OS" = "macos" ]; then
    CLAUDE_DESKTOP_CONFIG="${HOME}/Library/Application Support/Claude/claude_desktop_config.json"
    CLAUDE_DESKTOP_DIR="${HOME}/Library/Application Support/Claude"
    CLAUDE_DESKTOP_APP="/Applications/Claude.app"
    if [ -d "${CLAUDE_DESKTOP_APP}" ] || [ -d "${CLAUDE_DESKTOP_DIR}" ] || [ -f "${CLAUDE_DESKTOP_CONFIG}" ]; then
        _try_configure "Claude Desktop (macOS app)" \
            "${CLAUDE_DESKTOP_CONFIG}" "mcpServers" "alpax" "${ALPAX_BIN}"
    fi
else
    CLAUDE_DESKTOP_CONFIG="${HOME}/.config/Claude/claude_desktop_config.json"
    CLAUDE_DESKTOP_DIR="${HOME}/.config/Claude"
    if [ -d "${CLAUDE_DESKTOP_DIR}" ] || [ -f "${CLAUDE_DESKTOP_CONFIG}" ]; then
        _try_configure "Claude Desktop (Linux app)" \
            "${CLAUDE_DESKTOP_CONFIG}" "mcpServers" "alpax" "${ALPAX_BIN}"
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. CLAUDE CODE CLI  (the official Anthropic CLI tool, `claude` command)
# ──────────────────────────────────────────────────────────────────────────────
CLAUDE_CLI_CONFIG="${HOME}/.claude.json"
CLAUDE_CLI_DIR="${HOME}/.claude"
if command -v claude >/dev/null 2>&1 || [ -f "${CLAUDE_CLI_CONFIG}" ] || [ -d "${CLAUDE_CLI_DIR}" ]; then
    # Claude Code stores MCP servers in ~/.claude.json at top level
    _try_configure "Claude Code CLI" \
        "${CLAUDE_CLI_CONFIG}" "mcpServers" "alpax" "${ALPAX_BIN}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. CURSOR IDE  (standalone Electron app)
# ──────────────────────────────────────────────────────────────────────────────
CURSOR_MCP="${HOME}/.cursor/mcp.json"
CURSOR_DIR="${HOME}/.cursor"
if command -v cursor >/dev/null 2>&1 \
    || [ -d "${CURSOR_DIR}" ] \
    || [ -d "/Applications/Cursor.app" ] \
    || [ -d "${HOME}/Applications/Cursor.app" ]; then
    _try_configure "Cursor IDE" \
        "${CURSOR_MCP}" "mcpServers" "alpax" "${ALPAX_BIN}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. WINDSURF IDE  (Codeium's VS Code fork)
# ──────────────────────────────────────────────────────────────────────────────
WINDSURF_MCP="${HOME}/.codeium/windsurf/mcp_config.json"
WINDSURF_DIR="${HOME}/.codeium/windsurf"
if command -v windsurf >/dev/null 2>&1 \
    || [ -d "${WINDSURF_DIR}" ] \
    || [ -d "/Applications/Windsurf.app" ] \
    || [ -d "${HOME}/Applications/Windsurf.app" ]; then
    _try_configure "Windsurf IDE" \
        "${WINDSURF_MCP}" "mcpServers" "alpax" "${ALPAX_BIN}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 5. VS CODE + CONTINUE EXTENSION
# ──────────────────────────────────────────────────────────────────────────────
CONTINUE_CONFIG="${HOME}/.continue/config.json"
CONTINUE_DIR="${HOME}/.continue"
if [ -d "${CONTINUE_DIR}" ] || [ -f "${CONTINUE_CONFIG}" ]; then
    _try_configure "VS Code / Continue extension" \
        "${CONTINUE_CONFIG}" "mcpServers" "alpax" "${ALPAX_BIN}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 6. VS CODE + CLINE EXTENSION
#    Cline stores its MCP config at a known location in VS Code's storage
# ──────────────────────────────────────────────────────────────────────────────
# Detect VS Code / VS Codium / Code-OSS
_detect_vscode_storage() {
    local candidates=(
        "${HOME}/Library/Application Support/Code/User"   # macOS VS Code
        "${HOME}/.config/Code/User"                        # Linux VS Code
        "${HOME}/Library/Application Support/VSCodium/User"
        "${HOME}/.config/VSCodium/User"
        "${HOME}/Library/Application Support/Code - Insiders/User"
        "${HOME}/.config/Code - Insiders/User"
    )
    for d in "${candidates[@]}"; do
        if [ -d "$d" ]; then echo "$d"; return; fi
    done
}

VSCODE_STORAGE="$(_detect_vscode_storage)"

# Cline MCP config (stored in VS Code global storage or extension data)
CLINE_MCP="${HOME}/.cline/mcp_settings.json"
CLINE_DIR="${HOME}/.cline"
# Also check VS Code extension storage path for Cline
if [ -n "${VSCODE_STORAGE}" ]; then
    # Check common Cline extension storage paths
    for d in \
        "${VSCODE_STORAGE}/../globalStorage/saoudrizwan.claude-dev" \
        "${VSCODE_STORAGE}/../globalStorage/anthropic.claude-code"; do
        if [ -d "${d}" ]; then CLINE_DIR="${d}"; CLINE_MCP="${d}/settings/cline_mcp_settings.json"; break; fi
    done
fi
if [ -d "${CLINE_DIR}" ] || [ -f "${CLINE_MCP}" ]; then
    _try_configure "VS Code / Cline extension" \
        "${CLINE_MCP}" "mcpServers" "alpax" "${ALPAX_BIN}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 7. VS CODE + ROO CODE EXTENSION
# ──────────────────────────────────────────────────────────────────────────────
ROO_MCP="${HOME}/.roo/mcp.json"
ROO_DIR="${HOME}/.roo"
if [ -n "${VSCODE_STORAGE}" ]; then
    for d in "${VSCODE_STORAGE}/../globalStorage/rooveterinaryinc.roo-cline"; do
        if [ -d "${d}" ]; then ROO_DIR="${d}"; ROO_MCP="${d}/settings/mcp.json"; break; fi
    done
fi
if [ -d "${ROO_DIR}" ] || [ -f "${ROO_MCP}" ]; then
    _try_configure "VS Code / Roo Code extension" \
        "${ROO_MCP}" "mcpServers" "alpax" "${ALPAX_BIN}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 8. ZED EDITOR  (supports context servers, similar to MCP)
# ──────────────────────────────────────────────────────────────────────────────
ZED_CONFIG="${HOME}/.config/zed/settings.json"
ZED_CONFIG_ALT="${HOME}/Library/Application Support/Zed/settings.json"  # macOS
if [ -d "/Applications/Zed.app" ] || [ -d "${HOME}/.config/zed" ] || command -v zed >/dev/null 2>&1; then
    ZED_CFG="${ZED_CONFIG}"
    [ -f "${ZED_CONFIG_ALT}" ] && ZED_CFG="${ZED_CONFIG_ALT}"
    _try_configure_zed "${ZED_CFG}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 9. ANTIGRAVITY CLI  (Google DeepMind's Antigravity)
# ──────────────────────────────────────────────────────────────────────────────
AGY_MCP_DIR="${HOME}/.gemini/antigravity-cli/customizations/mcp-servers"
AGY_MCP_CONFIG="${AGY_MCP_DIR}/alpax/config.json"
if command -v agy >/dev/null 2>&1 || [ -d "${HOME}/.gemini/antigravity-cli" ]; then
    log_info "Found: ${BOLD}Antigravity CLI (agy)${RESET}"
    AGENTS_FOUND+=("Antigravity CLI")
    if confirm "  Configure Antigravity CLI to use Alpax?"; then
        mkdir -p "${AGY_MCP_DIR}/alpax"
        python3 - <<PYEOF
import json, os
cfg = {
    "name": "alpax",
    "description": "Alpax — local-first semantic code search and context squeezing",
    "command": "${ALPAX_BIN}",
    "args": [],
    "env": {}
}
with open('${AGY_MCP_CONFIG}', 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('ok')
PYEOF
        log_ok "Antigravity CLI configured → ${DIM}${AGY_MCP_CONFIG}${RESET}"
        AGENTS_CONFIGURED+=("Antigravity CLI")
    else
        log_info "Skipped Antigravity CLI"
        AGENTS_SKIPPED+=("Antigravity CLI")
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 10. NEOVIM + mcphub.nvim
# ──────────────────────────────────────────────────────────────────────────────
MCPHUB_CONFIG="${HOME}/.config/mcphub/servers.json"
if [ -d "${HOME}/.config/mcphub" ] || \
   [ -f "${HOME}/.local/share/nvim/lazy/mcphub.nvim/README.md" ] || \
   [ -d "${HOME}/.local/share/nvim/lazy/mcphub.nvim" ]; then
    _try_configure "Neovim / mcphub.nvim" \
        "${MCPHUB_CONFIG}" "servers" "alpax" "${ALPAX_BIN}"
fi

# ── No agents found? ──────────────────────────────────────────────────────────
if [ ${#AGENTS_FOUND[@]} -eq 0 ]; then
    log_warn "No AI coding agents detected on this system."
    log_info "After installing one (Claude Desktop, Cursor, Windsurf, etc.),"
    log_info "re-run this installer or add the config manually (see below)."
fi

# ── Step 6: PATH & shell RC ───────────────────────────────────────────────────
log_step 6 "Finalising PATH and environment"

_add_to_path() {
    local rc="$1"
    local line='export PATH="'"${BIN_DIR}"':$PATH"'
    [ -f "${rc}" ] && grep -q "${BIN_DIR}" "${rc}" 2>/dev/null && return
    {   echo ""
        echo "# Added by Alpax installer (https://github.com/${REPO})"
        echo "${line}"
    } >> "${rc}"
    log_ok "PATH updated in ${DIM}${rc}${RESET}"
}

case "${SHELL:-/bin/sh}" in
    */zsh)  _add_to_path "${HOME}/.zshrc" ;;
    */bash)
        _add_to_path "${HOME}/.bashrc"
        [ -f "${HOME}/.bash_profile" ] && _add_to_path "${HOME}/.bash_profile"
        ;;
    */fish)
        FISH_CONF="${HOME}/.config/fish/config.fish"
        mkdir -p "$(dirname "${FISH_CONF}")"
        if [ -f "${FISH_CONF}" ] && ! grep -q "${BIN_DIR}" "${FISH_CONF}" 2>/dev/null; then
            echo "" >> "${FISH_CONF}"
            echo "# Added by Alpax installer" >> "${FISH_CONF}"
            echo "fish_add_path ${BIN_DIR}" >> "${FISH_CONF}"
            log_ok "PATH updated in ${DIM}${FISH_CONF}${RESET}"
        fi
        ;;
    *)
        _add_to_path "${HOME}/.profile"
        ;;
esac

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║          🎉  Alpax is installed and ready!           ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "  ${DIM}Binary:${RESET}    ${ALPAX_BIN}"
echo -e "  ${DIM}Models:${RESET}    ${MODELS_DIR}"
echo -e "  ${DIM}Config:${RESET}    ${GLOBAL_CONFIG}"
echo -e "  ${DIM}Vector DB:${RESET} ${DB_DIR}  (auto-created per project)"
echo ""

if [ ${#AGENTS_CONFIGURED[@]} -gt 0 ]; then
    echo -e "  ${GREEN}Configured agents:${RESET}"
    for a in "${AGENTS_CONFIGURED[@]}"; do
        echo -e "    ${GREEN}✓${RESET}  ${a}"
    done
fi

if [ ${#AGENTS_SKIPPED[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}Skipped agents:${RESET}"
    for a in "${AGENTS_SKIPPED[@]}"; do
        echo -e "    ${YELLOW}○${RESET}  ${a}"
    done
fi

echo ""
echo -e "${BOLD}  How to use Alpax:${RESET}"
echo "    Open any configured AI agent and simply ask:"
echo ""
echo -e "    ${CYAN}\"Where is the authentication logic in this codebase?\"${RESET}"
echo "    ${DIM}or${RESET}"
echo -e "    ${CYAN}\"Show me how errors are handled in this project.\"${RESET}"
echo ""
echo "    Alpax automatically indexes your project on the first query"
echo "    and keeps it in sync via incremental BLAKE3 hashing."
echo ""

if [ ${#AGENTS_CONFIGURED[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}Restart your AI agent(s) for the changes to take effect.${RESET}"
fi

echo ""
echo "  Restart your terminal or run one of:"
echo -e "    ${DIM}source ~/.zshrc${RESET}   ${DIM}source ~/.bashrc${RESET}   ${DIM}source ~/.profile${RESET}"
echo ""

# Print manual config snippet for unconfigured agents
if [ ${#AGENTS_FOUND[@]} -eq 0 ] || [ ${#AGENTS_SKIPPED[@]} -gt 0 ]; then
    echo -e "  ${DIM}Manual MCP configuration snippet (for any agent that supports MCP):${RESET}"
    echo ""
    cat <<SNIPPET
  {
    "mcpServers": {
      "alpax": {
        "command": "${ALPAX_BIN}"
      }
    }
  }
SNIPPET
    echo ""
fi
